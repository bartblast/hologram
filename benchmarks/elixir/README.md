# Elixir Benchmarks

Last run: 2026-07-04 10:55:02 UTC

## Summary

Total benchmarks: 30

Successful: 26\
Warnings: 0\
Failed: 4

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          2.56      391.22 ms     ±3.27%      388.10 ms      428.05 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          4.14      241.67 ms     ±7.71%      236.95 ms      307.36 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          2.06      486.33 ms     ±1.11%      487.61 ms      495.35 ms
```


### ✅ compiler » build_module_digest_plt!_0

```
Name                                 ips        average  deviation         median         99th %
build_module_digest_plt!/0          4.16      240.58 ms     ±3.83%      240.70 ms      264.12 ms
```


### ❌ compiler » build_page_js_4

Failed with exit code: 1


### ❌ compiler » bundle_2

Failed with exit code: 1


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         46.32       21.59 ms    ±14.14%       19.43 ms       27.49 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file doesn't exist         21.63       46.22 ms    ±14.85%       44.80 ms       87.83 ms
dump dir exists, dump file exists                21.50       46.51 ms     ±3.52%       45.94 ms       57.17 ms
dump dir doesn't exists                          20.09       49.77 ms    ±21.00%       48.44 ms      131.96 ms

Comparison: 
dump dir exists, dump file doesn't exist         21.63
dump dir exists, dump file exists                21.50 - 1.01x slower +0.29 ms
dump dir doesn't exists                          20.09 - 1.08x slower +3.55 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1         65.36       15.30 ms    ±20.51%       13.75 ms       21.37 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                      141105.70     0.00709 ms    ±15.68%     0.00679 ms      0.0105 ms
1 module added                           2487.27        0.40 ms     ±6.58%        0.39 ms        0.50 ms
1 module removed                           71.27       14.03 ms    ±33.54%       15.49 ms       21.49 ms
1 added, 1 removed, 1 edited               62.25       16.06 ms    ±26.04%       17.55 ms       20.04 ms
1 module edited                            59.55       16.79 ms    ±23.53%       17.94 ms       22.40 ms
3 added, 3 removed, 3 edited               38.03       26.30 ms    ±14.63%       26.86 ms       31.60 ms
10 added, 10 removed, 10 edited            21.58       46.35 ms     ±7.27%       47.50 ms       50.21 ms
1% added, 1% removed, 1% edited            12.12       82.50 ms     ±6.14%       83.29 ms       91.70 ms
100% modules added                          4.09      244.46 ms     ±5.49%      240.56 ms      282.03 ms
100% modules removed                        0.71     1416.15 ms     ±1.17%     1410.23 ms     1446.96 ms
33% added, 33% removed, 34% edited          0.63     1580.43 ms     ±3.54%     1562.13 ms     1656.03 ms
100% modules edited                         0.26     3860.21 ms     ±2.37%     3859.36 ms     3952.10 ms

Comparison: 
no module changes                      141105.70
1 module added                           2487.27 - 56.73x slower +0.39 ms
1 module removed                           71.27 - 1979.75x slower +14.02 ms
1 added, 1 removed, 1 edited               62.25 - 2266.73x slower +16.06 ms
1 module edited                            59.55 - 2369.70x slower +16.79 ms
3 added, 3 removed, 3 edited               38.03 - 3710.69x slower +26.29 ms
10 added, 10 removed, 10 edited            21.58 - 6540.19x slower +46.34 ms
1% added, 1% removed, 1% edited            12.12 - 11641.34x slower +82.49 ms
100% modules added                          4.09 - 34494.05x slower +244.45 ms
100% modules removed                        0.71 - 199826.25x slower +1416.14 ms
33% added, 33% removed, 34% edited          0.63 - 223007.82x slower +1580.42 ms
100% modules edited                         0.26 - 544697.66x slower +3860.20 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1        1.34 M      746.70 ns    ±48.26%         667 ns     2184.76 ns
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2       20.21 K       49.48 μs     ±4.12%       49.17 μs       57.33 μs
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
2 vertices      1056.03 K        0.95 μs    ±40.84%        0.83 μs        2.69 μs
4 vertices       996.10 K        1.00 μs    ±35.92%        0.88 μs        2.25 μs
8 vertices       959.60 K        1.04 μs    ±30.42%           1 μs        2.25 μs
1 vertex         831.12 K        1.20 μs    ±61.48%        0.92 μs        3.38 μs
16 vertices      649.05 K        1.54 μs    ±31.82%        1.38 μs        3.54 μs
32 vertices      425.63 K        2.35 μs    ±18.05%        2.25 μs        4.23 μs

Comparison: 
2 vertices      1056.03 K
4 vertices       996.10 K - 1.06x slower +0.0570 μs
8 vertices       959.60 K - 1.10x slower +0.0952 μs
1 vertex         831.12 K - 1.27x slower +0.26 μs
16 vertices      649.05 K - 1.63x slower +0.59 μs
32 vertices      425.63 K - 2.48x slower +1.40 μs
```


### ❌ compiler » create_page_entry_files_4

Failed with exit code: 1


### ❌ compiler » create_runtime_entry_file_3

Failed with exit code: 1


### ✅ compiler » diff_module_digest_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                      4.47 K      223.89 μs     ±5.52%      220.96 μs      271.37 μs
100% modules added                        3.70 K      270.36 μs     ±7.77%      259.71 μs      361.83 μs
33% added, 33% removed, 34% edited        2.81 K      355.93 μs     ±6.98%      346.04 μs      445.75 μs
3 added, 3 removed, 3 edited              1.83 K      545.54 μs     ±3.10%      541.25 μs      619.92 μs
10 added, 10 removed, 10 edited           1.83 K      545.84 μs     ±3.57%      540.13 μs      619.41 μs
no module changes                         1.82 K      548.94 μs     ±2.67%      545.33 μs      605.82 μs
1 added, 1 removed, 1 edited              1.78 K      562.73 μs     ±2.93%      559.71 μs      618.50 μs
1 module removed                          1.77 K      565.07 μs     ±2.66%         564 μs      617.05 μs
1 module added                            1.76 K      567.38 μs     ±3.82%      566.71 μs      627.04 μs
1 module edited                           1.75 K      569.99 μs     ±2.58%      566.29 μs      624.20 μs
1% added, 1% removed, 1% edited           1.75 K      571.47 μs     ±3.88%      566.13 μs      640.84 μs
100% modules edited                       1.69 K      591.60 μs     ±7.32%      574.33 μs      744.90 μs

Comparison: 
100% modules removed                      4.47 K
100% modules added                        3.70 K - 1.21x slower +46.47 μs
33% added, 33% removed, 34% edited        2.81 K - 1.59x slower +132.04 μs
3 added, 3 removed, 3 edited              1.83 K - 2.44x slower +321.65 μs
10 added, 10 removed, 10 edited           1.83 K - 2.44x slower +321.95 μs
no module changes                         1.82 K - 2.45x slower +325.05 μs
1 added, 1 removed, 1 edited              1.78 K - 2.51x slower +338.84 μs
1 module removed                          1.77 K - 2.52x slower +341.17 μs
1 module added                            1.76 K - 2.53x slower +343.49 μs
1 module edited                           1.75 K - 2.55x slower +346.09 μs
1% added, 1% removed, 1% edited           1.75 K - 2.55x slower +347.58 μs
100% modules edited                       1.69 K - 2.64x slower +367.71 μs
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install        8.06 K      0.00012 s    ±15.05%      0.00012 s      0.00018 s
do install     0.00011 K         9.43 s     ±0.00%         9.43 s         9.43 s

Comparison: 
no install        8.06 K
do install     0.00011 K - 75978.10x slower +9.43 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      203.55 K     0.00491 ms   ±140.95%     0.00471 ms     0.00850 ms
do load      0.0136 K       73.66 ms     ±3.33%       73.09 ms       91.65 ms

Comparison: 
no load      203.55 K
do load      0.0136 K - 14993.90x slower +73.66 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load       88.23 K      0.0113 ms   ±123.16%     0.00975 ms      0.0296 ms
do load     0.00195 K      512.34 ms     ±1.74%      509.12 ms      528.28 ms

Comparison: 
no load       88.23 K
do load     0.00195 K - 45205.36x slower +512.33 ms
```


### ✅ compiler » maybe_load_module_digest_plt_1

```
Name              ips        average  deviation         median         99th %
no load       80.71 K       12.39 μs    ±56.73%       12.13 μs       19.79 μs
do load        2.01 K      497.75 μs     ±7.40%      491.17 μs      606.45 μs

Comparison: 
no load       80.71 K
do load        2.01 K - 40.17x slower +485.36 μs
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1      121.10 K        8.26 μs   ±102.72%        8.17 μs        9.46 μs
```


### ✅ mix » tasks » compile » hologram

```
Name                ips        average  deviation         median         99th %
has cache       47.64 K       20.99 μs    ±43.25%       19.08 μs       44.83 μs
no cache        30.16 K       33.15 μs    ±34.48%       30.75 μs       56.22 μs

Comparison: 
has cache       47.64 K
no cache        30.16 K - 1.58x slower +12.17 μs
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           163.29 M        6.12 ns  ±6018.32%        4.20 ns       12.50 ns
is atom                12.13 M       82.46 ns  ±9971.89%          42 ns          84 ns
is Erlang module       11.95 M       83.71 ns ±10300.41%          42 ns          84 ns
is Elixir module        8.89 M      112.47 ns  ±6566.36%          83 ns         125 ns

Comparison: 
is not atom           163.29 M
is atom                12.13 M - 13.46x slower +76.33 ns
is Erlang module       11.95 M - 13.67x slower +77.58 ns
is Elixir module        8.89 M - 18.37x slower +106.35 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           271.19 M        3.69 ns   ±201.63%        3.67 ns        3.83 ns
is Elixir module       16.50 M       60.62 ns  ±7289.50%          42 ns          84 ns
is Erlang module       14.38 M       69.55 ns  ±6564.43%          42 ns          84 ns
is atom               0.0734 M    13624.30 ns    ±47.91%       13125 ns       19417 ns

Comparison: 
is not atom           271.19 M
is Elixir module       16.50 M - 16.44x slower +56.93 ns
is Erlang module       14.38 M - 18.86x slower +65.86 ns
is atom               0.0734 M - 3694.81x slower +13620.61 ns
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3       15.43 M       64.81 ns  ±9684.78%          42 ns          84 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1       12.46 M       80.28 ns  ±6165.24%          83 ns          84 ns
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         55.26       18.10 ms     ±7.58%       17.94 ms       21.59 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         55.50       18.02 ms     ±7.20%       17.34 ms       21.38 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        232.06        4.31 ms     ±6.36%        4.28 ms        5.23 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            28.56 M       35.01 ns    ±51.01%          42 ns          42 ns
is Erlang module       21.85 M       45.77 ns  ±1832.64%          42 ns          42 ns
is Elixir module       21.04 M       47.54 ns  ±1859.59%          42 ns          83 ns
is atom               0.0683 M    14638.18 ns    ±50.10%       13291 ns       21917 ns

Comparison: 
is not atom            28.56 M
is Erlang module       21.85 M - 1.31x slower +10.76 ns
is Elixir module       21.04 M - 1.36x slower +12.52 ns
is atom               0.0683 M - 418.08x slower +14603.16 ns
```

