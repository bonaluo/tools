@echo off
@REM 参考 https://github.com/intel/ipex-llm/blob/main/docs/mddocs/Quickstart/ollama_quickstart.zh-CN.md
chcp 65001

@REM 使用 `call` 确保激活环境后，控制权返回到原始批处理文件继续执行后续命令
call C:\Users\XFYMT\miniconda3\Scripts\activate.bat C:\Users\XFYMT\miniconda3\envs\llm-cpp

cd /d c:\llama-cpp
set OLLAMA_NUM_GPU=999
set no_proxy=localhost,127.0.0.1
set ZES_ENABLE_SYSMAN=1
set SYCL_CACHE_PERSISTENT=1
set SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=1
set OLLAMA_HOST=0.0.0.0
ollama serve
