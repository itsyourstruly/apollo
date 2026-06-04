import sys

def replace_in_file(file_path, old_str, new_string):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if content.count(old_str) != 1:
        print(f"Error: found {content.count(old_str)} occurrences of old_string")
        sys.exit(1)
        
    content = content.replace(old_str, new_string)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

replace_in_file('apollo/ContentView.swift', '''enum IslandPage: Int, CaseIterable {
    case clipboard = 0
    case jot = 1
    case box = 2
}''', '''enum IslandPage: Int, CaseIterable {
    case clipboard = 0
    case jot = 1
    case box = 2
    case chrono = 3
}''')
