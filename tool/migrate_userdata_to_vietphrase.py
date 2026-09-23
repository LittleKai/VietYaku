# tool/migrate_userdata_to_vietphrase.py
#
# Di chuyển (migrate) các từ có trong thư mục userdata (SharedVietPhrase,
# VietPhrase overlay, UserDict, PendingVietPhrase, SharedLacViet)
# mà bộ từ điển gốc (data/jp, data/cn) chưa có.
#
# Cách chạy:
#   D:\Dev\conda-envs\py312\python.exe tool/migrate_userdata_to_vietphrase.py

import os
import shutil
import sys

def load_entries(filepath):
    entries = {}
    if not os.path.exists(filepath):
        return entries
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                k, v = line.split('=', 1)
                k = k.lstrip('\ufeff').strip()
                v = v.strip()
                entries[k] = v
    return entries

def append_new_entries(base_path, new_entries):
    if not new_entries:
        print(f'  {base_path}: Không có từ mới để thêm.')
        return 0
    
    # Read existing content
    with open(base_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    
    # Ensure starts with BOM
    has_bom = content.startswith('\ufeff')
    if not has_bom:
        content = '\ufeff' + content
    
    # Ensure ends with newline
    if not content.endswith('\n'):
        content += '\n'
        
    added = 0
    new_lines = []
    for k, v in new_entries.items():
        new_lines.append(f'{k}={v}\n')
        added += 1
        
    with open(base_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content + ''.join(new_lines))
        
    print(f'  {base_path}: Đã thêm {added} mục từ mới.')
    return added

def main():
    print('=== BẮT ĐẦU MIGRATE TỪ USERDATA VÀO VIETPHRASE ===\n')
    
    # ----------------------------------------------------
    # 1. Migrate Japanese VietPhrase
    # ----------------------------------------------------
    jp_base_path = 'data/jp/VietPhrase.txt'
    jp_base = load_entries(jp_base_path)
    print(f'1. Japanese VietPhrase hiện tại: {len(jp_base)} entries.')
    
    jp_sources = [
        'data/userdata/dictionaries/SharedVietPhrase_japanese.txt',
        'build/windows/x64/runner/Release/userdata/dictionaries/SharedVietPhrase_japanese.txt',
        'data/userdata/dictionaries/VietPhrase_japanese.txt',
        'data/userdata/dictionaries/PendingVietPhrase_japanese.txt',
        'build/windows/x64/runner/Release/userdata/dictionaries/PendingVietPhrase_japanese.txt',
        'data/userdata/dictionaries/UserDict.txt',
        'build/windows/x64/runner/Release/userdata/dictionaries/UserDict.txt',
    ]
    
    jp_new = {}
    for s in jp_sources:
        e = load_entries(s)
        for k, v in e.items():
            if 'DELETE' in v:
                if k in jp_new:
                    del jp_new[k]
                continue
            if not k or not v:
                continue
            if k not in jp_base:
                jp_new[k] = v
                
    print(f'   Tìm thấy {len(jp_new)} từ Nhật mới trong userdata.')
    append_new_entries(jp_base_path, jp_new)
    
    # ----------------------------------------------------
    # 2. Migrate Chinese VietPhrase
    # ----------------------------------------------------
    cn_base_path = 'data/cn/VietPhrase.txt'
    cn_base = load_entries(cn_base_path)
    print(f'\n2. Chinese VietPhrase hiện tại: {len(cn_base)} entries.')
    
    cn_sources = [
        'data/userdata/dictionaries/SharedVietPhrase_chinese.txt',
        'build/windows/x64/runner/Release/userdata/dictionaries/SharedVietPhrase_chinese.txt',
        'data/userdata/dictionaries/PendingGlossary_chinese.txt',
        'data/userdata/dictionaries/UserDict.txt',
        'build/windows/x64/runner/Release/userdata/dictionaries/UserDict.txt',
    ]
    
    cn_new = {}
    for s in cn_sources:
        e = load_entries(s)
        for k, v in e.items():
            if 'DELETE' in v:
                if k in cn_new:
                    del cn_new[k]
                continue
            if not k or not v:
                continue
            if k not in cn_base:
                cn_new[k] = v
                
    print(f'   Tìm thấy {len(cn_new)} từ Trung mới trong userdata.')
    append_new_entries(cn_base_path, cn_new)

    # ----------------------------------------------------
    # 3. Migrate Japanese LacViet (nếu có từ mới trong SharedLacViet)
    # ----------------------------------------------------
    jp_lv_path = 'data/jp/LacViet.txt'
    jp_lv_base = load_entries(jp_lv_path)
    print(f'\n3. Japanese LacViet hiện tại: {len(jp_lv_base)} entries.')
    
    lv_sources = [
        'data/userdata/dictionaries/SharedLacViet_japanese.txt',
        'build/windows/x64/runner/Release/userdata/dictionaries/SharedLacViet_japanese.txt',
        'data/userdata/dictionaries/PendingLacViet_japanese.txt',
        'build/windows/x64/runner/Release/userdata/dictionaries/PendingLacViet_japanese.txt',
    ]
    
    lv_new = {}
    for s in lv_sources:
        e = load_entries(s)
        for k, v in e.items():
            if 'DELETE' in v:
                if k in lv_new:
                    del lv_new[k]
                continue
            if not k or not v:
                continue
            if k not in jp_lv_base:
                lv_new[k] = v
                
    print(f'   Tìm thấy {len(lv_new)} từ LacViet mới trong userdata.')
    append_new_entries(jp_lv_path, lv_new)
    
    # ----------------------------------------------------
    # 4. Đồng bộ sang userdata/dictionaries (*_JP.txt) và xóa cache .vydc
    # ----------------------------------------------------
    print('\n4. Đồng bộ file *_JP.txt và xóa cache cũ...')
    targets = [
        ('data/userdata/dictionaries', 'data/userdata/cache'),
        ('build/windows/x64/runner/Release/userdata/dictionaries', 'build/windows/x64/runner/Release/userdata/cache'),
    ]
    for dict_dir, cache_dir in targets:
        if os.path.exists(dict_dir):
            shutil.copy2(jp_base_path, os.path.join(dict_dir, 'VietPhrase_JP.txt'))
            shutil.copy2(jp_lv_path, os.path.join(dict_dir, 'LacViet_JP.txt'))
            print(f'   Đã cập nhật VietPhrase_JP.txt & LacViet_JP.txt trong {dict_dir}')
        if os.path.exists(cache_dir):
            for c in os.listdir(cache_dir):
                if c.endswith('.vydc'):
                    os.remove(os.path.join(cache_dir, c))
            print(f'   Đã xóa toàn bộ cache .vydc trong {cache_dir}')
            
    print('\n=== MIGRATE HOÀN TẤT THÀNH CÔNG ===')

if __name__ == '__main__':
    main()
