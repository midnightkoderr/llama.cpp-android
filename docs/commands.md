# Sample commands

Install the variant(s) you need first — `llama-install cpu|gpu|npu|all` (see
the top-level [README](../README.md#install)) — then source that variant's
`env.sh` (or use its `run.sh` for a one-liner instead — see
[USAGE.md](USAGE.md)).

## NPU

```bash
source ~/llama.cpp/npu/env.sh
```

### llama cli

```bash
llama-cli -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 --no-mmap -p "capital of germany"
```

### llama server

```bash
llama-server -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 --no-mmap --port 8080
```

## GPU

```bash
source ~/llama.cpp/gpu/env.sh
```

### llama cli

```bash
llama-cli -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -ngl 1 -c 4096 --no-mmap -p "capital of germany"
```

### llama server

```bash
llama-server -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -ngl 1 -c 4096 --no-mmap --port 8080
```

## CPU

```bash
source ~/llama.cpp/cpu/env.sh
```

### llama cli

```bash
llama-cli -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -c 4096 --no-mmap -p "capital of germany"
```

### llama server

```bash
llama-server -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -c 4096 --no-mmap --port 8080
```
