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

如果 `matlab` 没有在系统 PATH 里：

- 修改 `start_portable_batch_windows.bat` 中的 `MATLAB_BIN`
- 例如改成：
  `set MATLAB_BIN=C:\Program Files\MATLAB\R2024b\bin\matlab.exe`

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
```

含义：

- `cfg.tensor_dir`：批量扫描整个目录下的 `*_tensor.mat`
- `cfg.tensor_files`：如果不为空，则只跑这里列出的文件

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
- 每个进程自动抢占不同样本

建议：

- 先从 `2` 开始
- 机器内存足够再试 `3` 或 `4`
- 如果每个 case 很重，不要盲目开太多

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

Windows 上最简单的方式：

双击：

- `start_portable_batch_windows.bat`

或者在命令行中执行：

```bat
start_portable_batch_windows.bat
```

它会调用：

```matlab
portable_run_batch
```

然后自动启动多个 worker。

## 6. 输出结构

每个 case 会在 `output_dir/case_id/` 下生成结果。

常见文件：

- `*_band.mat`
- `*_bands_hz.csv`
- `*_band_diagram.png`
- `*_band_diagram.svg`
- `*_bz_path.csv`
- `*_acoustic_band.mph`（如果 `save_model=true`）

其中：

- `*_band.mat` 适合后续数据集训练直接读取
- `*_bands_hz.csv` 适合快速检查 band 数值
- `*_acoustic_band.mph` 适合人工打开检查

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
- 可以中断后重启继续跑

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

1. 再给这个包补一个 Windows PowerShell 启动脚本
2. 直接把 `dist/` 实际生成出来并检查目录内容
