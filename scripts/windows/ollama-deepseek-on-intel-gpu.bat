@echo off
@REM 参考 https://github.com/intel/ipex-llm/blob/main/docs/mddocs/Quickstart/ollama_quickstart.zh-CN.md
@REM 在 Intel GPU 上直接免安装运行 Ollama https://github.com/intel/ipex-llm/blob/main/docs/mddocs/Quickstart/ollama_portablze_zip_quickstart.zh-CN.md
chcp 65001

@REM 使用 `call` 确保激活环境后，控制权返回到原始批处理文件继续执行后续命令
cd  C:\Users\XFYMT\miniconda3\condabin
call conda activate llm-cpp
@REM 和上面作用相同
@REM call C:\Users\XFYMT\miniconda3\Scripts\activate.bat C:\Users\XFYMT\miniconda3\envs\llm-cpp

cd /d c:\llama-cpp
set OLLAMA_NUM_GPU=999
set no_proxy=localhost,127.0.0.1
set ZES_ENABLE_SYSMAN=1
set SYCL_CACHE_PERSISTENT=1
set SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=1
set OLLAMA_HOST=0.0.0.0
@REM Ollama 默认每 5 分钟从 GPU 内存卸载一次模型。针对 ollama 的最新版本，你可以设置 OLLAMA_KEEP_ALIVE=-1 来将模型保持在显存上
set OLLAMA_KEEP_ALIVE=-1
@REM 通过设置OLLAMA_NUM_PARALLEL=1节省GPU内存，默认为4
set OLLAMA_NUM_PARALLEL=2
@REM 启用性能分析
set OLLAMA_ENABLE_PROFILING=1
ollama serve
