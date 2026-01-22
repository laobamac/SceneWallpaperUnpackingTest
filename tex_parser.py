import struct
import json
import os
import sys
from io import BytesIO

# ==========================================
# 依赖库检测
# ==========================================
try:
    import lz4.block
except ImportError:
    print("【注意】缺少 lz4 模块 (pip install lz4)。如果是压缩纹理，解压将失败。")
    lz4 = None

try:
    from PIL import Image
except ImportError:
    print("【注意】缺少 Pillow 模块 (pip install Pillow)。将只导出 .bin 原始数据。")
    Image = None

# ==========================================
# 工具类
# ==========================================
class TexFormat:
    RGBA8888, DXT5, DXT3, DXT1, RG88, R8 = 0, 4, 6, 7, 8, 9
    @staticmethod
    def to_string(fmt):
        return {0: "RGBA8888", 4: "DXT5", 6: "DXT3", 7: "DXT1", 8: "RG88", 9: "R8"}.get(fmt, f"Unknown({fmt})")

class DXTDecoder:
    """简易 DXT 解码器，用于将 DXT 纹理转换为 RGBA"""
    @staticmethod
    def unpack565(packed):
        r, g, b = (packed >> 11) & 0x1F, (packed >> 5) & 0x3F, packed & 0x1F
        return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2), 255)

    @staticmethod
    def decode(width, height, data, format):
        if format == TexFormat.RGBA8888: return data
        block_size = 8 if format == TexFormat.DXT1 else 16
        output = bytearray(width * height * 4)
        wb, hb = (width + 3) // 4, (height + 3) // 4
        
        for y in range(hb):
            for x in range(wb):
                off = (y * wb + x) * block_size
                if off + block_size > len(data): break
                block = data[off:off+block_size]
                
                c_off = 8 if format in (TexFormat.DXT3, TexFormat.DXT5) else 0
                c0, c1 = struct.unpack_from('<HH', block, c_off)
                colors = [DXTDecoder.unpack565(c0), DXTDecoder.unpack565(c1), (0,0,0,255), (0,0,0,255)]
                
                if format == TexFormat.DXT1 and c0 <= c1:
                    colors[2] = tuple((colors[0][i] + colors[1][i]) // 2 for i in range(3)) + (255,)
                else:
                    colors[2] = tuple((2*colors[0][i] + colors[1][i]) // 3 for i in range(3)) + (255,)
                    colors[3] = tuple((colors[0][i] + 2*colors[1][i]) // 3 for i in range(3)) + (255,)
                
                alphas = [255] * 16
                if format == TexFormat.DXT3:
                    bits = struct.unpack_from('<Q', block, 0)[0]
                    alphas = [((bits >> (i*4)) & 0xF) * 17 for i in range(16)]
                elif format == TexFormat.DXT5:
                    a0, a1 = block[0], block[1]
                    a_bits = int.from_bytes(block[2:8], 'little')
                    ac = [a0, a1] + [0]*6
                    if a0 > a1:
                        for i in range(1, 7): ac[i+1] = ((7-i)*a0 + i*a1)//7
                    else:
                        for i in range(1, 5): ac[i+1] = ((5-i)*a0 + i*a1)//5
                        ac[6], ac[7] = 0, 255
                    alphas = [ac[(a_bits >> (3*i)) & 7] for i in range(16)]

                indices = struct.unpack_from('<I', block, c_off+4)[0]
                for i in range(16):
                    px, py = x*4 + (i%4), y*4 + (i//4)
                    if px < width and py < height:
                        idx = (indices >> (2*i)) & 3
                        pixel_idx = (py * width + px) * 4
                        output[pixel_idx:pixel_idx+3] = colors[idx][:3]
                        output[pixel_idx+3] = alphas[i]
        return bytes(output)

class BinaryReader:
    def __init__(self, data):
        self.stream = BytesIO(data)
        self.size = len(data)

    def read_int32(self):
        try: return struct.unpack('<i', self.stream.read(4))[0]
        except: return 0
    
    def read_bytes(self, count):
        return self.stream.read(count)

    def read_string_v4_auto(self):
        """
        V4 JSON 字符串专用读取：
        自动判断是 [LengthPrefix + String] 还是 [NullTerminatedString]
        """
        pos = self.stream.tell()
        length_candidate = self.read_int32()
        
        # 判断逻辑：
        # 1. 如果长度是巨大的负数或极其巨大的正数 -> 肯定不是长度，可能是字符串内容
        # 2. 如果长度合理 (0-100KB)，且紧随其后的字节是可打印字符 -> 可能是长度前缀
        # 3. 如果长度看起来像 JSON 的开头 (例如 '{' 的 ASCII 是 123) -> 肯定是字符串内容
        
        is_length_prefix = False
        
        if 0 <= length_candidate < 100000:
            # 预读一下看看是不是 ASCII
            preview = self.stream.read(min(length_candidate, 10))
            self.stream.seek(pos + 4) # 回到长度之后
            # 简单判断：如果预读内容看起来像文本
            is_length_prefix = True 
        
        # 特例：如果 'length_candidate' 的第一个字节是 '{' (0x7B) 或 '[' (0x5B)，那它绝对是字符串本身
        first_byte = length_candidate & 0xFF
        if first_byte in [0x7B, 0x5B]: 
            is_length_prefix = False

        if is_length_prefix:
            # 按长度读取
            try:
                data = self.stream.read(length_candidate)
                return data.decode('utf-8', errors='ignore')
            except:
                return ""
        else:
            # 回退 4 字节，按 Null 结尾读取
            self.stream.seek(pos)
            chars = bytearray()
            while True:
                b = self.stream.read(1)
                if not b or b == b'\x00': break
                chars.extend(b)
            return chars.decode('utf-8', errors='ignore')

# ==========================================
# 核心逻辑
# ==========================================
def parse_tex(file_path, output_dir):
    print(f"========== 正在处理: {os.path.basename(file_path)} ==========")
    
    with open(file_path, 'rb') as f:
        file_data = f.read()
    reader = BinaryReader(file_data)
    
    # 1. 头部暴力搜寻 (防止 Magic 错位)
    header_offset = 0
    found = False
    for i in range(min(512, len(file_data) - 32)):
        reader.stream.seek(i)
        fmt = reader.read_int32()
        flags = reader.read_int32()
        tw = reader.read_int32()
        th = reader.read_int32()
        iw = reader.read_int32()
        ih = reader.read_int32()
        # 判定特征：Format在0-20之间，宽高合理
        if (0 <= fmt <= 20) and (0 < tw < 16384) and (0 < th < 16384):
            header_offset = i
            found = True
            break
            
    if not found:
        print("错误: 无法找到有效的文件头 (Format/Size校验失败)。")
        return

    reader.stream.seek(header_offset)
    tex_fmt = reader.read_int32()
    flags = reader.read_int32()
    tex_w = reader.read_int32()
    tex_h = reader.read_int32()
    img_w = reader.read_int32()
    img_h = reader.read_int32()
    reader.read_int32() # unk

    print(f"Header: 格式={TexFormat.to_string(tex_fmt)}({tex_fmt}), 尺寸={img_w}x{img_h}")

    # 2. 容器信息
    # 尝试读取 TEXB
    texb_str = ""
    texb_ver = 0
    
    # 在接下来的 32 字节内搜索 TEXB
    cur_pos = reader.stream.tell()
    peek = reader.read_bytes(32)
    texb_idx = peek.find(b'TEXB')
    
    if texb_idx != -1:
        reader.stream.seek(cur_pos + texb_idx)
        # 读 8 字节 TEXB000x
        texb_raw = reader.read_bytes(8)
        try:
            texb_str = texb_raw.decode('utf-8', errors='ignore')
            texb_ver = int(texb_str[-1])
        except: pass
        # 修正指针：TEXB字符串通常后接 ImageCount(int32)
        # 如果是 Native 格式，TEXB 后可能有 \0，也可能紧接 int
        # 简单处理：搜索完 TEXB 后，通常紧接着就是 image_count
        pass
    else:
        # 没找到 TEXB，可能是旧格式或极其精简，假设回退到 cur_pos 之后 4 字节
        reader.stream.seek(cur_pos)

    image_count = reader.read_int32()
    print(f"Container: {texb_str} (Ver {texb_ver}), ImageCount: {image_count}")

    if texb_ver == 3:
        reader.read_int32() # V3 Type

    # 3. 图像提取循环
    for i in range(image_count):
        mipmap_count = reader.read_int32()
        
        for j in range(mipmap_count):
            mw, mh = 0, 0
            mip_lz4 = False
            mip_decomp_size = 0
            
            # --- V4 关键修复区域 ---
            if texb_ver == 4:
                # 读取 V4 特有参数
                p1 = reader.read_int32()
                p2 = reader.read_int32()
                
                # 自适应读取 JSON
                json_str = reader.read_string_v4_auto()
                
                p3 = reader.read_int32()
                
                # 调试信息：如果这些看起来不对，说明偏移错了
                if j == 0:
                    print(f"[Debug V4] P1={p1}, P2={p2}, P3={p3}, JSONLen={len(json_str)}")
                
                # 读取标准参数
                mw = reader.read_int32()
                mh = reader.read_int32()
                mip_lz4 = (reader.read_int32() == 1)
                mip_decomp_size = reader.read_int32()
            
            elif texb_ver >= 2:
                mw = reader.read_int32()
                mh = reader.read_int32()
                mip_lz4 = (reader.read_int32() == 1)
                mip_decomp_size = reader.read_int32()
            
            else: # V1
                mw = reader.read_int32()
                mh = reader.read_int32()

            data_size = reader.read_int32()
            
            if j == 0:
                print(f"Mipmap 0 Info: {mw}x{mh}, LZ4={mip_lz4}, DecompSize={mip_decomp_size}, DataSize={data_size}")

            # 异常大小保护
            if data_size <= 0 or data_size > 200 * 1024 * 1024:
                print(f"错误: 数据大小异常 ({data_size})，跳过此文件。")
                return

            raw_data = reader.read_bytes(data_size)

            # 只处理 Mipmap 0
            if j == 0:
                final_data = raw_data
                
                # LZ4 解压
                if mip_lz4:
                    if lz4:
                        try:
                            # 尝试解压
                            # 注意：如果 decomp_size 读取错误（如0），则无法解压
                            d_size = mip_decomp_size if mip_decomp_size > 0 else mw * mh * 4
                            final_data = lz4.block.decompress(raw_data, uncompressed_size=d_size)
                            print(f"LZ4 解压成功: {len(raw_data)} -> {len(final_data)} bytes")
                        except Exception as e:
                            print(f"LZ4 解压失败: {e} (尝试使用原始数据)")
                            # 失败时不置为 None，而是保留原始数据，方便 dump 分析
                    else:
                        print("缺少 LZ4 库，无法解压。")

                # 导出部分
                base_name = os.path.splitext(os.path.basename(file_path))[0]
                
                # 1. 尝试保存为图片
                saved_img = False
                if Image:
                    try:
                        pil_img = None
                        # RGBA8888
                        if tex_fmt == TexFormat.RGBA8888:
                            # 宽松检查：如果数据量不够，尝试只读取能读的部分，或者填充
                            expected_len = mw * mh * 4
                            if len(final_data) < expected_len:
                                print(f"警告: 数据长度不足 (拥有 {len(final_data)}, 需要 {expected_len})，图片可能损坏。")
                                # 补零
                                final_data += b'\x00' * (expected_len - len(final_data))
                            
                            pil_img = Image.frombytes("RGBA", (mw, mh), final_data)

                        # DXT
                        elif tex_fmt in [TexFormat.DXT1, TexFormat.DXT3, TexFormat.DXT5]:
                            print("正在解码 DXT...")
                            decoded = DXTDecoder.decode(mw, mh, final_data, tex_fmt)
                            pil_img = Image.frombytes("RGBA", (mw, mh), decoded)
                        
                        # 其他
                        elif tex_fmt == TexFormat.R8:
                             pil_img = Image.frombytes("L", (mw, mh), final_data)
                        
                        if pil_img:
                            # 最终裁剪
                            if img_w > 0 and img_h > 0:
                                pil_img = pil_img.crop((0, 0, img_w, img_h))
                            
                            save_path = os.path.join(output_dir, f"{base_name}_{i}.png")
                            pil_img.save(save_path)
                            print(f"--> 图片已保存: {save_path}")
                            saved_img = True
                    except Exception as e:
                        print(f"图片转换失败: {e}")

                # 2. 兜底方案：保存原始数据
                # 如果没保存成图片，或者虽然保存了但用户想看原始数据
                if not saved_img:
                    bin_path = os.path.join(output_dir, f"{base_name}_{i}_raw.bin")
                    with open(bin_path, 'wb') as bf:
                        bf.write(final_data)
                    print(f"--> 已保存原始数据 (可用 RawPixels 查看): {bin_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python parse_tex_v4.py <文件路径> [输出目录]")
    else:
        file_path = sys.argv[1]
        out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(file_path)
        if not os.path.exists(out_dir): os.makedirs(out_dir)
        parse_tex(file_path, out_dir)