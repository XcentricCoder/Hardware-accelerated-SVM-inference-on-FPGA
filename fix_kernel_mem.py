with open('/home/sonan/rbf-kernel_inference/rbf-kernel_inference.srcs/sources_1/new/kernel_hex_only.mem', 'r') as f:
    lines = f.readlines()

clean_hex = []
for line in lines:
    if line.strip().startswith('//') or not line.strip():
        continue
    parts = line.split()
    if len(parts) >= 3:
        clean_hex.append(parts[2]) # Extract the 3rd column (Hex_Result)

with open('/home/sonan/rbf-kernel_inference/rbf-kernel_inference.srcs/sources_1/new/kernel_hex_only.mem', 'w') as f:
    for h in clean_hex:
        f.write(h + '\n')
