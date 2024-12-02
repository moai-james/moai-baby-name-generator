import re
import json

def parse_file(file_path):
    # 初始化結果字典
    result = {
        "characters": {},
        "byStrokes": {},
        "byElement": {
            "金": [], "木": [], "水": [], "火": [], "土": []
        }
    }
    
    current_strokes = 0
    
    line_num = 0
    with open(file_path, 'r', encoding='utf-8') as file:
        for line in file:
            line_num += 1
            line = line.strip()
            
            # 檢查是否是筆畫數行
            strokes_match = re.match(r'(\d+)畫：', line)
            if strokes_match:
                current_strokes = int(strokes_match.group(1))
                result["byStrokes"][str(current_strokes)] = []
                continue
                
            # 檢查是否是五行行

            element_match = re.match(r'五行屬「(.)」的字有：\s*(.*)$', line)
            if element_match:
                element = element_match.group(1)
                chars = element_match.group(2)
                print(f"✓ 第{line_num}行: 找到五行「{element}」")
                print(f"  - 字符: {chars}")
                
                # 分割字符
                if chars:
                    chars_list = list(chars)
                    
                    
                    # 更新每個字符的信息
                    for char in chars_list:
                        if char not in '：，。 ':  # 跳過標點符號
                            # 更新 characters
                            result["characters"][char] = {
                                "strokes": current_strokes,
                                "element": element
                            }
                            
                            # 更新 byStrokes
                            if str(current_strokes) not in result["byStrokes"]:
                                result["byStrokes"][str(current_strokes)] = []
                            if char not in result["byStrokes"][str(current_strokes)]:
                                result["byStrokes"][str(current_strokes)].append(char)
                            
                            # 更新 byElement
                            if char not in result["byElement"][element]:
                                result["byElement"][element].append(char)
    
    return result

def save_json(data, output_file):
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

# 執行轉換
input_file = 'moai-baby-name-generator/src.txt'  # 請更改為您的輸入文件路徑
output_file = 'moai-baby-name-generator/characters.json'        # 輸出文件名

try:
    data = parse_file(input_file)
    save_json(data, output_file)
    print(f"轉換完成！已保存至 {output_file}")
    
    # 輸出一些統計信息
    print(f"\n統計信息：")
    print(f"總字數：{len(data['characters'])}")
    print(f"筆畫數範圍：{min(map(int, data['byStrokes'].keys()))} - {max(map(int, data['byStrokes'].keys()))}")
    for element in data['byElement']:
        print(f"{element}：{len(data['byElement'][element])}字")
        
except Exception as e:
    print(f"發生錯誤：{str(e)}")