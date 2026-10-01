import random

N = 5  # matrix size: DEPTH = SIZE = N_WR = N

BIT_WIDTH = 8  # element width in bits
ACC_WIDTH = 32  # accumulator width in bits
SEED = None  # set an int for reproducible output, or leave None
OUT_DIR = "./sim"


def write_hex_matrix(path, rows, cols, values, hex_digits):
    with open(path, "w") as f:
        f.write(f"// {rows}x{cols}, row-major, hex\n")
        for i in range(rows):
            row = values[i * cols:(i + 1) * cols]
            f.write(" ".join(f"{v:0{hex_digits}x}" for v in row) + "\n")


def main():
    if SEED is not None:
        random.seed(SEED)

    elem_max = (1 << BIT_WIDTH) - 1
    weight = [random.randint(0, elem_max) for _ in range(N * N)]
    inp = [random.randint(0, elem_max) for _ in range(N * N)]

    # output[a][c] = sum over r of input[a][r] * weight[r][c]
    acc_max = (1 << ACC_WIDTH) - 1
    output = []
    for a in range(N):
        for c in range(N):
            total = sum(inp[a * N + r] * weight[r * N + c] for r in range(N))
            if total > acc_max:
                print(f"warning: output[{a}][{c}]={total} overflows "
                      f"ACC_WIDTH={ACC_WIDTH} (max {acc_max})")
            output.append(total & acc_max)

    elem_hex_digits = (BIT_WIDTH + 3) // 4
    acc_hex_digits = (ACC_WIDTH + 3) // 4

    write_hex_matrix(f"{OUT_DIR}/weight_matrix.txt", N, N, weight, elem_hex_digits)
    write_hex_matrix(f"{OUT_DIR}/input_matrix.txt", N, N, inp, elem_hex_digits)
    write_hex_matrix(f"{OUT_DIR}/output_matrix.txt", N, N, output, acc_hex_digits)

    print(f"wrote weight_matrix.txt, input_matrix.txt, output_matrix.txt ({N}x{N}) to {OUT_DIR}")


if __name__ == "__main__":
    main()