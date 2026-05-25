@echo off
"matlab" -batch "try, run_band_dataset_worker('D:\Desktop\portable_batch_package_dist\dist\output\batch_config.mat'); catch ME, disp(getReport(ME,'extended')); exit(1); end; exit(0);" > "D:\Desktop\portable_batch_package_dist\dist\output\worker_01.log" 2>&1
