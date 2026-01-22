import struct
import os
import sys
import json

class BinaryReader:
    def __init__(self, data):
        self.data = data
        self.pos = 0
        self.size = len(data)

    def seek(self, offset):
        self.pos = offset

    def skip(self, amount):
        self.pos += amount

    def read_bytes(self, count):
        if self.pos + count > self.size:
            raise EOFError(f"Unexpected end of file at {self.pos} (requested {count} bytes)")
        res = self.data[self.pos : self.pos + count]
        self.pos += count
        return res

    def peek_bytes(self, count):
        return self.data[self.pos : min(self.pos + count, self.size)]

    def read_int32(self):
        return struct.unpack('<i', self.read_bytes(4))[0]

    def read_uint32(self):
        return struct.unpack('<I', self.read_bytes(4))[0]

    def read_int16(self):
        return struct.unpack('<h', self.read_bytes(2))[0]

    def read_uint16(self):
        return struct.unpack('<H', self.read_bytes(2))[0]

    def read_float(self):
        return struct.unpack('<f', self.read_bytes(4))[0]

    def read_str(self):
        chars = []
        while self.pos < self.size:
            try:
                b = self.read_bytes(1)
            except EOFError:
                break
            if b == b'\0':
                break
            chars.append(b.decode('utf-8', errors='ignore'))
        return "".join(chars)

    def read_version(self, prefix):
        # Based on C++ logic: Read 9 bytes. Check prefix. Parse integer from offset 4.
        # e.g. "MDLV0013\0" -> prefix "MDL" matches, number is at [4:8] -> "0013"
        try:
            raw = self.read_bytes(9)
        except EOFError:
            return 0, "EOF"

        s_raw = raw.decode('utf-8', errors='ignore').strip('\x00')
        
        # Check prefix (e.g. "MDL")
        if not s_raw.startswith(prefix):
            return 0, s_raw
        
        # Parse version number (skip first 4 chars, e.g. "MDLV")
        try:
            version_part = s_raw[4:8]
            if version_part.isdigit():
                return int(version_part), s_raw
            return 0, s_raw
        except IndexError:
            return 0, s_raw

def find_signature_offset(data, signature, start_offset=0):
    sig_bytes = signature.encode('utf-8')
    return data.find(sig_bytes, start_offset)

def parse_mdl(file_path):
    print(f"Processing: {file_path}")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    file_name = os.path.basename(file_path)
    base_name = os.path.splitext(file_name)[0]
    
    output_obj = os.path.join(script_dir, base_name + ".obj")
    output_json = os.path.join(script_dir, base_name + "_data.json")

    try:
        with open(file_path, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        print(f"[ERROR] File not found: {file_path}")
        return

    reader = BinaryReader(data)
    
    export_data = {
        "info": {},
        "skinning": [],
        "skeleton": [],
        "animations": []
    }
    
    obj_vertices = []
    obj_uvs = []
    obj_faces = []

    try:
        mdl_version, raw_ver = reader.read_version("MDL")
        print(f"MDL Version: {mdl_version} (Raw: {raw_ver})")
        
        mdl_flag = reader.read_int32()
        reader.read_int32() # unk
        reader.read_int32() # unk
        mat_json_file = reader.read_str()
        reader.read_int32() # 0

        export_data["info"]["version"] = mdl_version
        export_data["info"]["flag"] = mdl_flag
        export_data["info"]["material_file"] = mat_json_file

        alt_mdl_format = False
        curr = reader.read_uint32()
        std_herald = 0x01800009
        alt_herald = 0x0180000F
        
        if curr == 0:
            alt_mdl_format = True
            print("Format: Alternative MDL")
            while curr != alt_herald and reader.pos < reader.size:
                curr = reader.read_uint32()
            curr = reader.read_uint32()
        elif curr == std_herald:
            curr = reader.read_uint32()
        
        vertex_size = curr
        stride = 80 if alt_mdl_format else 52
        
        if stride == 0 or vertex_size % stride != 0:
             print(f"[WARN] Vertex size alignment issue. Size: {vertex_size}, Stride: {stride}")

        vertex_count = vertex_size // stride
        print(f"Vertices: {vertex_count}")

        for i in range(vertex_count):
            vx, vy, vz = reader.read_float(), reader.read_float(), reader.read_float()
            obj_vertices.append((vx, vy, vz))
            
            if alt_mdl_format: 
                reader.read_bytes(28) # Skip 7 ints

            b_indices = [reader.read_uint32() for _ in range(4)]
            weights = [reader.read_float() for _ in range(4)]
            
            export_data["skinning"].append({
                "vertex_id": i,
                "bone_indices": b_indices,
                "weights": weights
            })

            tu, tv = reader.read_float(), reader.read_float()
            obj_uvs.append((tu, tv))

        indices_size = reader.read_uint32()
        tri_count = indices_size // 6
        print(f"Triangles: {tri_count}")

        for _ in range(tri_count):
            obj_faces.append((reader.read_uint16(), reader.read_uint16(), reader.read_uint16()))

    except Exception as e:
        print(f"[ERROR] Mesh parsing failed: {e}")
        # Even if mesh fails, we try to save what we have? Probably useless, but let's continue.

    # Search for MDLS signature globally
    mdls_offset = find_signature_offset(data, "MDLS", 0)
    
    if mdls_offset != -1:
        print(f"\nFound MDLS at offset {mdls_offset}. Parsing Skeleton...")
        reader.seek(mdls_offset)
        try:
            mdls_ver, _ = reader.read_version("MDL") 
            section_size = reader.read_uint32()
            bone_count = reader.read_uint16()
            reader.read_uint16() # unk
            
            print(f"  Skeleton Ver: {mdls_ver}, Bones: {bone_count}")
            
            # Sanity check for bone count
            if 0 < bone_count < 10000:
                for i in range(bone_count):
                    bone_name = reader.read_str()
                    reader.read_int32() # unk
                    parent = reader.read_uint32()
                    size = reader.read_uint32()
                    
                    matrix = []
                    if size == 64:
                        matrix = [reader.read_float() for _ in range(16)]
                    else:
                        reader.read_bytes(size) # Skip unknown size
                    
                    sim_json = reader.read_str()
                    
                    export_data["skeleton"].append({
                        "id": i,
                        "name": bone_name,
                        "parent": parent,
                        "matrix": matrix,
                        "sim_config": sim_json
                    })
                print("  Skeleton parsed successfully.")
            else:
                print("  [WARN] Suspicious bone count, skipping skeleton.")
        except Exception as e:
            print(f"  [WARN] Skeleton parsing interrupted: {e}")
    else:
        print("\nMDLS signature not found.")

    mdla_offset = find_signature_offset(data, "MDLA", 0)
    
    if mdla_offset != -1:
        print(f"\nFound MDLA at offset {mdla_offset}. Parsing Animations...")
        # read_version logic expects 9 bytes. Manually adjust to MDLA structure.
        # MDLA header usually: "MDLA" (4 bytes) + Version (4 bytes string? or int?)
        # Let's trust read_version("MDL") to handle "MDLAxxxx"
        reader.seek(mdla_offset)
        
        try:
            mdla_ver, raw_ver = reader.read_version("MDL") 
            print(f"  Animation Ver: {mdla_ver} (Raw: {raw_ver})")

            # Check validity
            if mdla_ver > 0:
                end_size = reader.read_uint32()
                anim_num = reader.read_uint32()
                print(f"  Animation Count: {anim_num}")
                
                # Sanity check for animation count
                if anim_num > 10000:
                    print("  [WARN] Animation count too high, skipping.")
                    anim_num = 0

                for i in range(anim_num):
                    try:
                        # Skip 0 padding between animations
                        anim_id = 0
                        while anim_id == 0:
                            if reader.pos >= reader.size - 4:
                                break
                            anim_id = reader.read_int32()
                        
                        if anim_id == 0: break # End of list
                        
                        reader.read_int32() # unk
                        anim_name = reader.read_str()
                        if not anim_name: anim_name = reader.read_str() # double read sometimes
                        
                        play_mode = reader.read_str()
                        fps = reader.read_float()
                        length = reader.read_int32()
                        reader.read_int32() # unk
                        
                        bone_frames_count = reader.read_uint32()
                        
                        anim_entry = {
                            "id": anim_id,
                            "name": anim_name,
                            "mode": play_mode,
                            "fps": fps,
                            "length": length,
                            "track_count": bone_frames_count,
                            "tracks": []
                        }
                        
                        # Parse Bone Tracks
                        for _ in range(bone_frames_count):
                            track_id = reader.read_int32()
                            byte_size = reader.read_uint32()
                            
                            if reader.pos + byte_size > reader.size:
                                print(f"    [ERR] Track {track_id} size {byte_size} exceeds file bounds.")
                                reader.seek(reader.size)
                                break
                            
                            # 36 bytes per frame (3 floats * 3 vectors = 9 floats * 4 bytes)
                            frames_num = byte_size // 36
                            
                            # Optional: Just read raw bytes to save memory/speed if not needed
                            # reader.read_bytes(byte_size)
                            
                            # Parse detailed frames
                            frames = []
                            for _ in range(frames_num):
                                p = [reader.read_float() for _ in range(3)]
                                r = [reader.read_float() for _ in range(3)]
                                s = [reader.read_float() for _ in range(3)]
                                frames.append({"p": p, "r": r, "s": s})
                            
                            # Handle remaining padding bytes if byte_size wasn't exactly frames * 36
                            remainder = byte_size - (frames_num * 36)
                            if remainder > 0:
                                reader.read_bytes(remainder)

                            anim_entry["tracks"].append({
                                "track_id": track_id,
                                "frames": frames
                            })

                        export_data["animations"].append(anim_entry)

                    except EOFError:
                        print(f"  [WARN] EOF reached inside animation {i}. Stopping animation parse.")
                        break
                    except Exception as e:
                        print(f"  [WARN] Error parsing animation {i}: {e}. Skipping.")
                        continue
            
                print(f"  Parsed {len(export_data['animations'])} animations.")
                
        except Exception as e:
            print(f"  [WARN] MDLA header parsing failed: {e}")
    else:
        print("\nMDLA signature not found.")

    try:
        with open(output_obj, 'w') as f:
            f.write(f"# Exported from {file_name}\n")
            f.write(f"mtllib {os.path.basename(export_data['info'].get('material_file', 'unknown.mtl')).replace('.json', '.mtl')}\n")
            for v in obj_vertices:
                f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
            for uv in obj_uvs:
                f.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
            for face in obj_faces:
                f1, f2, f3 = face[0]+1, face[1]+1, face[2]+1
                f.write(f"f {f1}/{f1} {f2}/{f2} {f3}/{f3}\n")
        print(f"\n[SUCCESS] OBJ saved to: {output_obj}")
    except Exception as e:
        print(f"[ERROR] Could not save OBJ: {e}")

    try:
        with open(output_json, 'w', encoding='utf-8') as f:
            json.dump(export_data, f, indent=2, ensure_ascii=False)
        print(f"[SUCCESS] Extra data saved to: {output_json}")
    except Exception as e:
        print(f"[ERROR] Could not save JSON: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python mdl_parser_final.py <input.mdl>")
    else:
        parse_mdl(sys.argv[1])