import os
import struct

NUM_GAMES = 2000

def write_configs(filename: str, configs: list) -> None:
    with open(filename, "wb") as f:
        f.write(struct.pack("<q", len(configs)))
        for k, p, n, m in configs:
            f.write(struct.pack("<ifii", k, p, n, m))

def make_configs() -> list:
    capitals = [10, 20, 30, 40, 50]
    probs = [0.30, 0.40, 0.45, 0.50, 0.55, 0.60, 0.70]
    target = 100
    return [(k, p, target, NUM_GAMES) for k in capitals for p in probs]

def main() -> None:
    base = os.path.dirname(os.path.abspath(__file__))
    configs = make_configs()

    write_configs(os.path.join(base, "same_data.bin"), configs)
    write_configs(os.path.join(base, "seq_data.bin"), configs)
    write_configs(os.path.join(base, "parallel_data.bin"), configs)

if __name__ == "__main__":
    main()
