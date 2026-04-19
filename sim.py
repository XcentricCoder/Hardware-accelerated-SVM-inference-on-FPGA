def to_signed(val, bits):
    if val >= (1 << (bits - 1)):
        val -= (1 << bits)
    return val

def to_hex(val, bits):
    if val < 0:
        val += (1 << bits)
    return f"{val:0{bits//4}x}"

intercept = 0x019d
# emulate padding: {{4{intercept[15]}}, intercept, 12'b0}
# intercept is 16 bits
int_signed = to_signed(intercept, 16)
accum = int_signed << 12

print(f"Init accum: {to_hex(accum, 32)}")

alpha = 0xF100
kernel = 0x0320
alpha_s = to_signed(alpha, 16)
kernel_s = to_signed(kernel, 16)
prod = alpha_s * kernel_s
accum += prod
# truncate to 32 bits
accum = to_signed(accum & 0xFFFFFFFF, 32)
print(f"Prod: {to_hex(prod & 0xFFFFFFFF, 32)}")
print(f"Accum: {to_hex(accum, 32)}")
