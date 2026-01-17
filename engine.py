import pygame
from pygame.locals import *
from OpenGL.GL import *
from OpenGL.GL import shaders
import json
import os
import time
import numpy as np
from PIL import Image

# =================配置区域=================
WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 720
SCENE_FILE = "scene.json"
# =========================================

VERTEX_SHADER = """
#version 330 core
in vec2 position;
in vec2 texcoord;
uniform mat4 projection;
uniform mat4 model;
out vec2 v_texcoord;
void main()
{
    gl_Position = projection * model * vec4(position, 0.0, 1.0);
    v_texcoord = texcoord;
}
"""

FRAGMENT_SHADER_BASE = """
#version 330 core
in vec2 v_texcoord;
out vec4 out_color;
uniform sampler2D texture0;
void main()
{
    vec4 col = texture(texture0, v_texcoord);
    if(col.a < 0.01) discard;
    out_color = col;
}
"""

FRAGMENT_SHADER_WAVE = """
#version 330 core
in vec2 v_texcoord;
out vec4 out_color;

uniform sampler2D texture0;
uniform sampler2D texture1;

uniform float g_Time;
uniform float g_Speed;
uniform float g_Strength;
uniform float g_Scale;
uniform float g_Exponent;
uniform float g_Direction;

void main()
{
    float mask = texture(texture1, v_texcoord).r;
    vec2 dirVec = vec2(sin(g_Direction), cos(g_Direction));
    vec2 texCoordMotion = v_texcoord;
    
    float distance = g_Time * g_Speed + dot(texCoordMotion, dirVec) * g_Scale;
    float strength = g_Strength * g_Strength;
    vec2 offset = vec2(dirVec.y, -dirVec.x);
    
    float val1 = sin(distance);
    float s1 = sign(val1);
    val1 = pow(abs(val1), g_Exponent);
    
    vec2 newTexCoord = v_texcoord + val1 * s1 * offset * strength * mask;
    
    if(newTexCoord.x < 0.0 || newTexCoord.x > 1.0 || newTexCoord.y < 0.0 || newTexCoord.y > 1.0) {
        // newTexCoord = v_texcoord; 
    }
    
    vec4 col = texture(texture0, newTexCoord);
    if(col.a < 0.01) discard;
    out_color = col;
}
"""

def load_texture(path):
    path = path.replace("\\", "/")
    
    # ==========================================================
    # 核心修复：强制路径映射，不再依赖文件是否存在
    # ==========================================================
    # 如果路径以 .json 结尾，说明它指向的是模型定义，我们需要的是同名的材质图片
    if path.endswith(".json"):
        # 逻辑：models/xxx.json -> materials/xxx.png
        # 1. 尝试标准映射
        candidate = path.replace("models/", "materials/").replace(".json", ".png")
        if os.path.exists(candidate):
            path = candidate
        else:
            # 2. 尝试只要文件名匹配的 materials 目录下的图片
            filename = os.path.basename(path).replace(".json", ".png")
            candidate_2 = os.path.join("materials", filename)
            if os.path.exists(candidate_2):
                path = candidate_2
            else:
                # 3. 实在找不到，打印错误但不崩渍
                print(f"跳过：找不到对应的图片资源 -> {path}")
                return None

    # 如果还没找到（或者本来就不是json），做最后的检查
    if not os.path.exists(path):
        # 尝试在该路径的 materials 文件夹下找
        filename = os.path.basename(path)
        candidate_3 = os.path.join("materials", filename)
        if os.path.exists(candidate_3):
            path = candidate_3
        else:
            return None

    try:
        # 打开图片
        img = Image.open(path).convert("RGBA")
        img_data = np.array(list(img.getdata()), np.uint8)
        
        tex_id = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, tex_id)
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img.width, img.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, img_data)
        glGenerateMipmap(GL_TEXTURE_2D)
        
        print(f"成功加载纹理: {os.path.basename(path)}")
        return tex_id
    except Exception as e:
        print(f"纹理加载异常 {path}: {e}")
        return None

def main():
    pygame.init()
    
    # macOS Core Profile 配置
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MAJOR_VERSION, 3)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_MINOR_VERSION, 3)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_PROFILE_MASK, pygame.GL_CONTEXT_PROFILE_CORE)
    pygame.display.gl_set_attribute(pygame.GL_CONTEXT_FORWARD_COMPATIBLE_FLAG, True) 
    
    pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT), DOUBLEBUF | OPENGL | RESIZABLE)
    pygame.display.set_caption("WE Native Engine - macOS Final Fix")

    # VAO 绑定 (macOS 必需)
    vao = glGenVertexArrays(1)
    glBindVertexArray(vao)

    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glClearColor(0.1, 0.1, 0.1, 1.0)

    try:
        shader_base = shaders.compileProgram(
            shaders.compileShader(VERTEX_SHADER, GL_VERTEX_SHADER),
            shaders.compileShader(FRAGMENT_SHADER_BASE, GL_FRAGMENT_SHADER)
        )
        shader_wave = shaders.compileProgram(
            shaders.compileShader(VERTEX_SHADER, GL_VERTEX_SHADER),
            shaders.compileShader(FRAGMENT_SHADER_WAVE, GL_FRAGMENT_SHADER)
        )
    except Exception as e:
        print("着色器编译失败:", e)
        return

    # 准备顶点数据
    quad_buffer = glGenBuffers(1)
    vertices = np.array([
        -0.5, -0.5, 0.0, 1.0,
         0.5, -0.5, 1.0, 1.0,
         0.5,  0.5, 1.0, 0.0,
        -0.5,  0.5, 0.0, 0.0
    ], dtype=np.float32)
    
    glBindBuffer(GL_ARRAY_BUFFER, quad_buffer)
    glBufferData(GL_ARRAY_BUFFER, vertices.nbytes, vertices, GL_STATIC_DRAW)

    # 加载场景
    if not os.path.exists(SCENE_FILE):
        print(f"错误：找不到 {SCENE_FILE}")
        return

    with open(SCENE_FILE, 'r', encoding='utf-8') as f:
        scene_data = json.load(f)

    objects = []
    canvas_w = 3840
    canvas_h = 2160
    
    if 'orthogonalprojection' in scene_data.get('camera', {}):
        canvas_w = scene_data['camera']['orthogonalprojection']['width']
        canvas_h = scene_data['camera']['orthogonalprojection']['height']

    print("开始加载资源...")
    
    for obj in scene_data.get('objects', []):
        if 'image' not in obj: continue 

        # 跳过看起来像脚本或特效的非实体层
        if not obj['image'].startswith('models/'): 
             # 一些粒子特效也用image字段，但不是我们能渲染的图层
             if not obj['image'].endswith('.json') and not obj['image'].endswith('.png'):
                 continue

        tex_id = load_texture(obj['image'])
        if tex_id is None: continue

        origin = list(map(float, obj['origin'].split()))
        if 'size' in obj:
            size = list(map(float, obj['size'].split()))
        else:
            size = [canvas_w, canvas_h]
            
        render_obj = {
            'tex': tex_id,
            'pos': (origin[0], origin[1]), 
            'size': (size[0], size[1]),
            'shader': shader_base,
            'params': {}
        }

        if 'effects' in obj:
            for eff in obj['effects']:
                if 'waterwaves' in eff['file']:
                    render_obj['shader'] = shader_wave
                    pass_data = eff['passes'][0]
                    vals = pass_data['constantshadervalues']
                    
                    mask_tex = None
                    if 'textures' in pass_data and len(pass_data['textures']) > 1:
                        mask_path = pass_data['textures'][1]
                        # Mask 也是同样的逻辑，需要强制找图片
                        if mask_path:
                            mask_tex = load_texture(mask_path)
                            # 如果load_texture内部没找到，它会返回None，我们再试一次拼接 materials
                            if mask_tex is None and not mask_path.startswith("materials"):
                                 mask_tex = load_texture("materials/" + mask_path)

                    render_obj['mask'] = mask_tex
                    render_obj['params'] = {
                        'g_Speed': float(vals.get('speed', 1.0)),
                        'g_Strength': float(vals.get('strength', 0.1)),
                        'g_Scale': float(vals.get('scale', 50.0)),
                        'g_Exponent': float(vals.get('exponent', 1.0)),
                        'g_Direction': float(vals.get('direction', 0.0))
                    }
                    break
        
        objects.append(render_obj)

    print(f"加载完成，渲染对象数: {len(objects)}")

    clock = pygame.time.Clock()
    running = True
    start_time = time.time()

    while running:
        for event in pygame.event.get():
            if event.type == QUIT:
                running = False
            elif event.type == VIDEORESIZE:
                glViewport(0, 0, event.w, event.h)

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        
        current_time = time.time() - start_time
        
        L, R, B, T = 0, canvas_w, 0, canvas_h
        ortho_mat = np.array([
            [2/(R-L), 0, 0, -(R+L)/(R-L)],
            [0, 2/(T-B), 0, -(T+B)/(T-B)],
            [0, 0, -1, 0],
            [0, 0, 0, 1]
        ], dtype=np.float32).T 

        for obj in objects:
            prog = obj['shader']
            glUseProgram(prog)
            
            proj_loc = glGetUniformLocation(prog, "projection")
            glUniformMatrix4fv(proj_loc, 1, GL_FALSE, ortho_mat)
            
            w, h = obj['size']
            x, y = obj['pos']
            
            scale_mat = np.array([
                [w, 0, 0, 0],
                [0, h, 0, 0],
                [0, 0, 1, 0],
                [0, 0, 0, 1]
            ], dtype=np.float32)
            
            trans_mat = np.array([
                [1, 0, 0, 0],
                [0, 1, 0, 0],
                [0, 0, 1, 0],
                [x, y, 0, 1] 
            ], dtype=np.float32)
            
            model_mat = np.dot(scale_mat, trans_mat) 
            
            model_loc = glGetUniformLocation(prog, "model")
            glUniformMatrix4fv(model_loc, 1, GL_FALSE, model_mat)
            
            glActiveTexture(GL_TEXTURE0)
            glBindTexture(GL_TEXTURE_2D, obj['tex'])
            glUniform1i(glGetUniformLocation(prog, "texture0"), 0)
            
            if prog == shader_wave:
                if obj.get('mask'):
                    glActiveTexture(GL_TEXTURE1)
                    glBindTexture(GL_TEXTURE_2D, obj['mask'])
                    glUniform1i(glGetUniformLocation(prog, "texture1"), 1)
                
                params = obj['params']
                glUniform1f(glGetUniformLocation(prog, "g_Time"), current_time)
                glUniform1f(glGetUniformLocation(prog, "g_Speed"), params['g_Speed'])
                glUniform1f(glGetUniformLocation(prog, "g_Strength"), params['g_Strength'])
                glUniform1f(glGetUniformLocation(prog, "g_Scale"), params['g_Scale'])
                glUniform1f(glGetUniformLocation(prog, "g_Exponent"), params['g_Exponent'])
                glUniform1f(glGetUniformLocation(prog, "g_Direction"), params['g_Direction'])

            glBindBuffer(GL_ARRAY_BUFFER, quad_buffer)
            
            pos_loc = glGetAttribLocation(prog, "position")
            glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 4 * 4, ctypes.c_void_p(0))
            glEnableVertexAttribArray(pos_loc)
            
            tex_loc = glGetAttribLocation(prog, "texcoord")
            glVertexAttribPointer(tex_loc, 2, GL_FLOAT, GL_FALSE, 4 * 4, ctypes.c_void_p(2 * 4))
            glEnableVertexAttribArray(tex_loc)
            
            glDrawArrays(GL_TRIANGLE_FAN, 0, 4)

        pygame.display.flip()
        clock.tick(60)

if __name__ == "__main__":
    main()