# Portable MATLAB + COMSOL Batch Package

这是一套可复制到另一台机器上直接运行的 B-spline 声学能带批处理包。

目标用途：

- 输入一批 `*_tensor.mat`
- 自动重构 B-spline 隐式场
- 自动根据对称群选择高对称 `k-path`
- 调用 MATLAB + COMSOL LiveLink 计算 band
- 支持多进程并行
- 输出 `band.mat`、`bands_hz.csv`、band 图、可选 `.mph`

## 1. 目标机器前提

目标机器需要满足：

- 已安装 MATLAB
- 已安装 COMSOL Multiphysics
- 已安装 COMSOL LiveLink for MATLAB
- 在 MATLAB 里可以正常调用 `mphstart`
- `matlab -batch` 可以从命令行启动

如果 worker 用的 `matlab` 没有在系统 PATH 里：

- 修改 `portable_runner/portable_batch_config_template.m` 中的 `cfg.worker_matlab_bin`
- 例如改成：
  `cfg.worker_matlab_bin = 'C:\Program Files\MATLAB\R2024b\bin\matlab.exe';`

## 2. 包内目录结构

复制后的包结构应类似：

```text
portable_batch_package/
  README.md
  start_portable_batch_windows.bat
  portable_runner/
    portable_add_paths.m
    portable_batch_config_template.m
    portable_run_batch.m
  acoustic_band_comsol/
    *.m
  FEA_Engine/
    Math_Utils/
      PrecomputeBasisMatrix_Unified.m
    Symmetry_Engine/
      GetSpaceGroupConfig.m
```

你只需要复制整个这个目录，不要拆开复制。

## 3. 最重要的配置文件

所有主要参数集中在：

- `portable_runner/portable_batch_config_template.m`

你通常只需要改这个文件。

## 4. 最常改的参数

### 4.1 数据集路径

默认示例：

```matlab
cfg.tensor_dir = 'D:\path\to\your\tensor_dataset';
cfg.tensor_files = {};
cfg.task_index_start = [];
cfg.task_index_end = [];
```

含义：

- `cfg.tensor_dir`：批量扫描整个目录下的 `*_tensor.mat`
- `cfg.tensor_files`：如果不为空，则只跑这里列出的文件
- `cfg.task_index_start/task_index_end`：在稳定排序后的任务列表上截取一个闭区间

二选一的推荐方式：

1. 跑整个目录

```matlab
cfg.tensor_dir = 'D:\dataset\bspline\tensors';
cfg.tensor_files = {};
```

2. 只跑指定若干样本

```matlab
cfg.tensor_files = { ...
    'D:\dataset\bspline\tensors\p4_Vol0.53_K0.0000_Sample_103461_tensor.mat', ...
    'D:\dataset\bspline\tensors\p4mm_Vol0.31_K0.0000_Sample_100987_tensor.mat'};
```

如果设置了 `tensor_files`，它会优先于 `tensor_dir`。

### 4.1.1 多机群分片运行

如果你要把同一个包放到不同机群上跑，推荐每个机群使用不同的 `output_dir`，并给每次运行指定不重叠的任务范围：

```matlab
cfg.tensor_dir = 'D:\dataset\bspline\tensors';
cfg.tensor_files = {};
cfg.task_index_start = 1;
cfg.task_index_end = 1000;
cfg.output_dir = 'D:\band_output\cluster_a';
```

另一组机器可以改成：

```matlab
cfg.task_index_start = 1001;
cfg.task_index_end = 2000;
cfg.output_dir = 'D:\band_output\cluster_b';
```

规则：

- 索引是 MATLAB 风格的 `1`-based
- 范围是闭区间，`start` 和 `end` 都包含
- 如果只设置 `task_index_start`，则表示从该位置一直跑到最后
- 如果 `task_index_end` 超过实际任务数，会自动截断到最后一个任务
- `worker_count` 只控制单个机群内部的并行，不影响分片边界

排序稳定性说明：

- 自动扫描 `tensor_dir` 时，程序会先收集 `*_tensor.mat`
- 然后按文件名做显式升序排序，再按范围切片
- 因此不会依赖不同操作系统返回目录项的原始顺序
- 为了便于核对，本次运行实际采用的顺序还会写入 `output_dir/task_manifest.csv`

### 4.1.2 COMSOL with MATLAB 路径配置

推荐模式是：

- 你先手动打开 `COMSOL with MATLAB`
- 在这个主会话里运行 `portable_run_batch`
- 主会话负责生成配置并启动多个 worker
- 每个 worker 用普通 `matlab -batch` 启动
- 每个 worker 进程内显式加载 LiveLink，并各自启动独立 COMSOL server

因此你需要编辑：

- `portable_runner/portable_batch_config_template.m`

默认关键字段：

```matlab
cfg.worker_launch_mode = 'matlab';
cfg.worker_matlab_bin = 'matlab';
cfg.comsol_root = 'D:\Software\COMSOL\COMSOL63\Multiphysics';
cfg.comsol_mli_dir = fullfile(cfg.comsol_root, 'mli');
cfg.comsol_host = '127.0.0.1';
cfg.comsol_reuse_existing_server = false;
cfg.comsol_np = 2;
cfg.comsol_hide_server_window = true;
cfg.enable_worker_comsol_recovery = true;
cfg.case_infra_retry_limit = 1;
cfg.worker_infra_failure_limit = 3;
cfg.worker_recovery_backoff_s = 5;
cfg.worker_healthcheck_before_claim = true;
cfg.enable_batch_summary = false;
```

含义：

- `worker_launch_mode = 'matlab'`
  - 这是当前唯一推荐模式
  - worker 始终用普通 `matlab -batch` 启动
- `comsol_mli_dir`
  - COMSOL LiveLink 的 `mli` 目录
  - worker 启动后会先 `addpath(...)`
- `comsol_root`
  - COMSOL Multiphysics 安装根目录
  - worker 用它来启动独立 `comsolmphserver`
- `comsol_reuse_existing_server = false`
  - 默认每个 worker 使用独立 server
  - 不推荐多个 worker 共享同一个 server
- `comsol_np = 2`
  - 限制每个 worker 自己启动的 COMSOL server 使用多少个核
  - `0` 表示不显式限制，交给 COMSOL 默认行为
  - 只有 `comsol_reuse_existing_server = false` 时才生效
- `comsol_hide_server_window = true`
  - Windows 下隐藏每个 worker 启动的 COMSOL server 命令窗口
  - Linux 上忽略这个选项
- `enable_worker_comsol_recovery = true`
  - worker 遇到 COMSOL 连接失效、server 崩溃或 OOM 类异常时尝试恢复
- `case_infra_retry_limit = 1`
  - 单个 case 在基础设施异常后的最大重试次数
- `worker_infra_failure_limit = 3`
  - 连续基础设施故障达到阈值后，worker 停止 claim 新任务并退出
- `worker_recovery_backoff_s = 5`
  - 每次恢复前等待几秒，避免 server 崩溃后高速重试
- `worker_healthcheck_before_claim = true`
  - 每次 claim 新 case 前先做 LiveLink / COMSOL 健康检查
- `enable_batch_summary = false`
  - 默认不写 `batch_summary_events.csv` / `batch_summary.csv`
  - 可以减少 worker 常驻时的文件锁、CSV 解析和快照刷新开销
  - 如果你需要运行中状态表，再手动改回 `true`

高级选项：如果你明确要让所有 worker 连接已有共享 server，可以改成：

```matlab
cfg.comsol_reuse_existing_server = true;
cfg.comsol_host = '127.0.0.1';
cfg.comsol_port = 2036;
```

说明：

- 这时 `cfg.comsol_np` 不会生效
- 因为 worker 不再启动新 server，而是连接你事先已经启动好的共享 server
- 如果要限制共享 server 的核数，需要在你手动启动那个 COMSOL server 时设置

### 4.2 输出路径

默认：

```matlab
cfg.output_dir = fullfile(paths.package_root, 'output');
```

可以改成：

```matlab
cfg.output_dir = 'D:\comsol_band_output\run_001';
```

### 4.3 并行进程数

```matlab
cfg.worker_count = 2;
```

含义：

- 不是单个 COMSOL 求解器内部多线程
- 而是同时启动多个 MATLAB 进程
- 每个进程会先通过共享 cursor 领取下一个候选任务，再用 case `.lock` 防止重复计算

建议：

- 先从 `2` 开始
- 机器内存足够再试 `3` 或 `4`
- 如果每个 case 很重，不要盲目开太多
- 结合 `cfg.comsol_np` 一起估算总预算
- 对 64 核机器可先试 `cfg.worker_count = 20; cfg.comsol_np = 2;`

### 4.4 分辨率、k 点数、band 数

```matlab
cfg.grid_resolution = 256;
cfg.field_grid_resolution = 256;
cfg.total_k_points = 71;
cfg.num_eigenfrequencies = 4;
```

含义：

- `grid_resolution`：几何重构分辨率
- `field_grid_resolution`：每个 `k` 点场图采样分辨率
- `total_k_points`：整条高对称路径总采样点数
- `num_eigenfrequencies`：每个 `k` 点求多少条 band

### 4.5 黑白实体定义

```matlab
cfg.solid_phase_value = 1;
```

规则：

- `solid_phase_value = 1`
  - 把图中的黑色/`mat==1` 认定为实体
- `solid_phase_value = 0`
  - 把图中的白色/`mat==0` 认定为实体

如果你要跑“黑白反相版”数据集，就把它改成：

```matlab
cfg.solid_phase_value = 0;
```

### 4.6 是否保存 `.mph`

```matlab
cfg.save_model = true;
```

建议：

- 调试阶段：`true`
- 大规模正式生成数据：如果磁盘压力大可设为 `false`

### 4.7 是否导出标准图和 CSV

```matlab
cfg.write_standard_outputs = true;
```

建议：

- 调试阶段：`true`
- 如果只想要 `band.mat`，可以考虑 `false`

## 5. 如何启动

推荐入口只有一个：

1. 手动打开 `COMSOL with MATLAB`
2. 在该会话里运行：

```matlab
run(fullfile('D:\path\to\portable_batch_package','portable_runner','portable_run_batch.m'))
```

或者如果当前目录已经在包根目录，也可以直接运行：

```matlab
portable_run_batch
```

主脚本会：

- 加载包内路径
- 解析任务列表，按文件名稳定排序并应用 `task_index_start/task_index_end`
- 读取 `portable_batch_config_template.m`
- 生成 `output/batch_config.mat`
- 生成 `output/task_manifest.csv`
- 如果 `enable_batch_summary = true`
  - 在 worker claim/完成 case 时追加写入 `output/batch_summary_events.csv`
  - 定期从事件日志刷新 `output/batch_summary.csv` 快照
- 生成 `output/launch_worker_*.bat`
- 自动启动多个 worker

兼容入口：

- 根目录的 `start_portable_batch_windows.bat` 仍可用
- 但它只是历史兼容路径，不再是默认推荐入口

注意：

- 不要手动双击 `output/launch_worker_01.bat` 之类的文件
- 这些只是主程序自动生成的 worker 启动脚本
- 推荐入口始终是 `COMSOL with MATLAB` 主会话里的 `portable_run_batch`

### 5.1 Windows 清锁与停 worker

仓库新增 Windows 管理脚本：

- `cleanup_portable_batch_windows.bat`
- `cleanup_portable_batch_windows.ps1`
- `control_workers_windows.bat`
- `control_workers_windows.ps1`

用途：

- `cleanup_portable_batch_windows`
  - 删除输出目录下的 `.lock`、`.batch_summary.lock`、`.comsol_server_start.lock`、`.task_cursor.lock`
  - 删除 `.task_cursor.txt` 和 batch summary 事件/快照计数文件
  - 停止和该 `output_dir` 对应的 MATLAB worker 及其子进程
- `control_workers_windows`
  - `status`：查看匹配到的 worker 和子进程
  - `stop`：停止匹配到的 worker 和子进程

用法：

```bat
cleanup_portable_batch_windows.bat output
control_workers_windows.bat output status
control_workers_windows.bat output stop
```

如果你输出目录不是默认的 `output`，把第一个参数换成对应目录名或绝对路径即可。

## 6. 输出结构

每个 case 会在 `output_dir/case_id/` 下生成结果。

常见文件：

- `task_manifest.csv`
- `batch_summary_events.csv`（仅 `enable_batch_summary = true` 时）
- `batch_summary.csv`（仅 `enable_batch_summary = true` 时）
- `*_band.mat`
- `*_bands_hz.csv`
- `*_band_diagram.png`
- `*_band_diagram.svg`
- `*_bz_path.csv`
- `*_acoustic_band.mph`（如果 `save_model=true`）

其中：

- `task_manifest.csv` 记录这次运行真正使用的任务顺序、索引和源文件路径
- `batch_summary_events.csv` 是追加式事件日志；仅在 `enable_batch_summary = true` 时写入
- `batch_summary.csv` 是从事件日志定期刷新的最新状态快照；仅在 `enable_batch_summary = true` 时写入
- `batch_summary.csv` 最适合查看已经被 worker 触达的 case 的 `running/ok/error`
- 两个文件都会记录 `failure_kind`、`infra_recovery_attempts`、`worker_exit_reason`
- `*_band.mat` 适合后续数据集训练直接读取
- `*_bands_hz.csv` 适合快速检查 band 数值
- `*_acoustic_band.mph` 适合人工打开检查

当前任务分发策略：

- 同一个 `output_dir` 下的所有 worker 共享一个 `.task_cursor.txt`
- worker 领取任务时先锁住 `.task_cursor.lock`，读取当前索引，再把 cursor 写到下一个索引
- cursor 负责避免所有 worker 反复从头扫描全任务列表
- case 目录下的 `.lock` 仍然保留，用来保证同一个 case 不会被两个 worker 同时真正执行
- 当 cursor 到达末尾后，worker 会再做一次全表重扫，用来捞起中途异常退出后可能遗留的未完成 case

## 7. 已支持的文件名风格

目前同时支持从文件名里自动识别对称群：

1. 仓库原始十例风格

```text
01_p4_100139_tensor.mat
```

2. 外部大数据集风格

```text
p4_Vol0.53_K0.0000_Sample_103461_tensor.mat
```

不需要你手工再传 `symmetry_group`。

## 8. 断点续跑

默认：

```matlab
cfg.skip_completed = true;
```

含义：

- 已经生成 `*_band.mat` 且存在 `.done` 的 case 会自动跳过
- 如果只有旧 `.done` 而没有 `*_band.mat`，不会被跳过
- 可以中断后重启继续跑

续跑兼容性：

- 如果旧批次已经停掉，可以在同一个 `output_dir` 上直接继续跑新版本
- 新版本第一次写状态时，如果只看到旧的 `batch_summary.csv`，会自动引导生成新的 `batch_summary_events.csv`
- 不建议让“旧版本 worker”和“新版本 worker”同时对同一个 `output_dir` 混跑；计算结果通常不会重复，但汇总文件机制不同，状态记录会变得不干净

## 8.1 Worker 自动恢复与熔断

worker 现在会区分两类错误：

- 普通 case 错误
  - 当前 case 记为 `error`
  - worker 继续处理后续 case
- 基础设施错误
  - 例如 COMSOL server 失联、LiveLink 断开、Java/内存/OOM 类错误
  - worker 会尝试恢复自己的 COMSOL 会话
  - 恢复成功后，当前 case 最多按 `case_infra_retry_limit` 重试
  - 恢复失败或连续失败过多时，worker 停止 claim 新任务并退出

worker 熔断退出时，日志里会有固定标记：

```text
WORKER_INFRA_RECOVERY_FAILED
WORKER_EXITING_NO_MORE_CLAIMS
```

推荐用外部脚本、任务调度器或进程守护层在 worker 非零退出后重新拉起对应 worker。

## 9. 常见修改示例

### 示例 A：跑整个目录，黑色为实体

```matlab
cfg.tensor_dir = 'D:\dataset\bspline\tensors';
cfg.tensor_files = {};
cfg.output_dir = 'D:\band_output\solid_is_one';
cfg.worker_count = 3;
cfg.solid_phase_value = 1;
cfg.grid_resolution = 256;
cfg.field_grid_resolution = 256;
cfg.total_k_points = 71;
cfg.num_eigenfrequencies = 4;
```

### 示例 B：跑整个目录，白色为实体

```matlab
cfg.tensor_dir = 'D:\dataset\bspline\tensors';
cfg.output_dir = 'D:\band_output\solid_is_zero';
cfg.solid_phase_value = 0;
```

### 示例 C：只跑 10 个指定样本

```matlab
cfg.tensor_files = { ...
    'D:\dataset\bspline\tensors\p4_Vol0.53_K0.0000_Sample_103461_tensor.mat', ...
    'D:\dataset\bspline\tensors\p4mm_Vol0.31_K0.0000_Sample_100987_tensor.mat'};
cfg.output_dir = 'D:\band_output\subset10';
cfg.worker_count = 2;
```

### 示例 D：机群 A 跑第 1 到 1000 个

```matlab
cfg.tensor_dir = 'D:\dataset\bspline\tensors';
cfg.tensor_files = {};
cfg.task_index_start = 1;
cfg.task_index_end = 1000;
cfg.output_dir = 'D:\band_output\cluster_a';
cfg.worker_count = 3;
```

### 示例 E：机群 B 跑第 1001 到 2000 个

```matlab
cfg.tensor_dir = 'D:\dataset\bspline\tensors';
cfg.tensor_files = {};
cfg.task_index_start = 1001;
cfg.task_index_end = 2000;
cfg.output_dir = 'D:\band_output\cluster_b';
cfg.worker_count = 3;
```

## 10. 如果要重新生成这个便携包

在当前仓库里运行：

```matlab
build_portable_batch_package
```

生成目录在：

```text
bspline/acoustic_band_comsol/portable_batch_package/dist
```

如果你愿意，我下一步可以继续帮你做两件事之一：

1. 给 Windows 版再补一个可传参的 PowerShell 启动脚本
2. 直接把 `dist/` 实际生成出来并检查目录内容
