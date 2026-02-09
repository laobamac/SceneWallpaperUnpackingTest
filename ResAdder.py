import os
import json
import shutil
import sys

VALID_EXTENSIONS = {'.png', '.webp', '.tga', '.mp4'}

def get_json_files(directory):
    json_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.lower().endswith('.json'):
                json_files.append(os.path.join(root, file))
    return json_files

def extract_texture_paths(json_path):
    paths = set()
    try:
        with open(json_path, 'r', encoding='utf-8', errors='ignore') as f:
            data = json.load(f)
        
        def recursive_search(obj):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    if key in ['textures', 'texture', 'image'] and isinstance(value, (str, list)):
                        if isinstance(value, str):
                            paths.add(value)
                        elif isinstance(value, list):
                            for item in value:
                                if isinstance(item, str):
                                    paths.add(item)
                    else:
                        recursive_search(value)
            elif isinstance(obj, list):
                for item in obj:
                    recursive_search(item)

        recursive_search(data)
    except Exception:
        pass
    
    return paths

def find_asset_file(assets_root, relative_path):
    prefixes = [
        "materials",
        "",
        "particles"
    ]
    
    clean_rel_path = relative_path.replace('\\', '/')
    
    for prefix in prefixes:
        search_base = os.path.join(assets_root, prefix, clean_rel_path)
        
        for ext in VALID_EXTENSIONS:
            candidate = search_base
            if not os.path.splitext(candidate)[1]:
                candidate += ext
            else:
                base = os.path.splitext(search_base)[0]
                candidate = base + ext
                
            if os.path.exists(candidate):
                return candidate
                
    return None

def main():
    args = sys.argv[1:]
    force_overwrite = False
    if '-f' in args:
        force_overwrite = True
        args.remove('-f')

    if len(args) < 2:
        print("Usage: python3 Res_Adder.py [-f] <Assets_Dir> <Wallpaper_Dir>")
        return

    assets_dir = args[0]
    wallpaper_dir = args[1]

    if not os.path.exists(assets_dir):
        print(f"Error: Assets directory not found: {assets_dir}")
        return

    print(f"Scanning wallpaper directory: {wallpaper_dir} ...")
    
    json_files = get_json_files(wallpaper_dir)
    print(f"Found {len(json_files)} JSON files.")

    missing_files = set()

    for jf in json_files:
        paths = extract_texture_paths(jf)
        for p in paths:
            if " " in p and "." not in p: continue 
            missing_files.add(p)

    print(f"Analyzing {len(missing_files)} potential references.")
    
    copied_count = 0
    
    for rel_path in missing_files:
        target_path_A = os.path.join(wallpaper_dir, "materials", rel_path)
        target_path_B = os.path.join(wallpaper_dir, rel_path)
        
        found_locally = False
        for ext in VALID_EXTENSIONS:
            pA = target_path_A if os.path.splitext(target_path_A)[1] else target_path_A + ext
            pB = target_path_B if os.path.splitext(target_path_B)[1] else target_path_B + ext
            
            if os.path.exists(pA):
                found_locally = True; break
            if os.path.exists(pB):
                found_locally = True; break
        
        if found_locally and not force_overwrite:
            continue

        src_file = find_asset_file(assets_dir, rel_path)
        
        if src_file:
            dest_rel = rel_path.replace('\\', '/')
            ext = os.path.splitext(src_file)[1]
            if not dest_rel.endswith(ext):
                dest_rel += ext
                
            dest_path = os.path.join(wallpaper_dir, "materials", dest_rel)
            
            if dest_rel.startswith("materials/"):
                dest_path = os.path.join(wallpaper_dir, dest_rel)

            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            try:
                shutil.copy2(src_file, dest_path)
                print(f"Copied: {os.path.basename(src_file)} -> {dest_path}")
                copied_count += 1
            except Exception as e:
                print(f"Failed to copy {src_file}: {e}")

    print(f"Done. Copied {copied_count} files from Assets.")

if __name__ == "__main__":
    main()