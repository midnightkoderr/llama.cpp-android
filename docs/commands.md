# Sample commands

## NPU

### llama cli

```bash
llama-cli -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 --no-mmap -p "capital of germany"
```

### llama server

```bash
llama-server -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf --device HTP0 -ngl 99 -c 4096 --no-mmap --port 8080
```

## GPU

### llama cli

```bash
llama-cli -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -ngl 1 -c 4096 --no-mmap -p "capital of germany"
```

### llama server

```bash
llama-server -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -ngl 1 -c 4096 --no-mmap --port 8080
```

## CPU

### llama cli

```bash
llama-cli -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -c 4096 --no-mmap -p "capital of germany"
```

## ## llama server

```bash
llama-server -m sdcard/llm-models/Llama-3.2-3B-Instruct-Q4_0.gguf -c 4096 --no-mmap --port 8080
```
