import codecs
import os

try:
    with codecs.open('DriveSizeStrings_temp.rc', 'r', 'utf-8') as source:
        content = source.read()
    
    with open('DriveSizeStrings.rc', 'wb') as target:
        target.write(codecs.BOM_UTF16_LE)
        target.write(content.encode('utf-16-le'))
        
    print("Conversion successful.")
except Exception as e:
    print(f"Error: {e}")
