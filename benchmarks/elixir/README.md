# Elixir Benchmarks

Last run: 2025-10-21 17:58:25 UTC

## Summary

Total benchmarks: 31

Successful: 31\
Warnings: 0\
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          2.50      400.11 ms     ±5.83%      392.32 ms      494.88 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          3.71      269.87 ms     ±3.45%      268.73 ms      311.06 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          2.93      341.47 ms     ±1.75%      340.62 ms      362.95 ms
```


### ✅ compiler » build_module_digest_plt!_0

```
Name                                 ips        average  deviation         median         99th %
build_module_digest_plt!/0          4.67      214.13 ms     ±3.40%      214.89 ms      228.49 ms
```


### ✅ compiler » build_page_js_4

```
Name                      ips        average  deviation         median         99th %
build_page_js/4        122.63        8.15 ms    ±17.88%        8.99 ms       10.48 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          5.15      194.04 ms     ±2.67%      193.57 ms      207.25 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         51.78       19.31 ms    ±13.72%       17.53 ms       24.05 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file exists                25.06       39.91 ms     ±6.15%       39.23 ms       57.67 ms
dump dir exists, dump file doesn't exist         25.01       39.99 ms     ±4.86%       39.64 ms       54.92 ms
dump dir doesn't exists                          24.49       40.83 ms     ±5.17%       40.28 ms       55.81 ms

Comparison: 
dump dir exists, dump file exists                25.06
dump dir exists, dump file doesn't exist         25.01 - 1.00x slower +0.0785 ms
dump dir doesn't exists                          24.49 - 1.02x slower +0.93 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1         63.40       15.77 ms     ±1.24%       15.72 ms       16.63 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                      175303.86     0.00570 ms    ±32.26%     0.00525 ms      0.0120 ms
1 module added                           2942.44        0.34 ms    ±19.15%        0.33 ms        0.74 ms
1 module removed                          224.96        4.45 ms    ±73.69%        2.11 ms       13.04 ms
1 module edited                           174.71        5.72 ms    ±56.46%        3.83 ms       13.56 ms
1 added, 1 removed, 1 edited              151.36        6.61 ms    ±42.92%        4.65 ms       12.20 ms
3 added, 3 removed, 3 edited               86.75       11.53 ms    ±23.84%        9.90 ms       17.28 ms
10 added, 10 removed, 10 edited            31.51       31.74 ms     ±9.68%       31.77 ms       38.40 ms
1% added, 1% removed, 1% edited            23.07       43.34 ms     ±5.93%       43.61 ms       47.72 ms
100% modules added                          9.22      108.48 ms     ±5.53%      108.11 ms      123.71 ms
100% modules removed                        0.91     1103.56 ms     ±1.08%     1099.71 ms     1124.22 ms
33% added, 33% removed, 34% edited          0.85     1178.18 ms     ±5.74%     1151.89 ms     1325.87 ms
100% modules edited                         0.35     2886.80 ms     ±0.56%     2887.42 ms     2904.84 ms

Comparison: 
no module changes                      175303.86
1 module added                           2942.44 - 59.58x slower +0.33 ms
1 module removed                          224.96 - 779.27x slower +4.44 ms
1 module edited                           174.71 - 1003.42x slower +5.72 ms
1 added, 1 removed, 1 edited              151.36 - 1158.18x slower +6.60 ms
3 added, 3 removed, 3 edited               86.75 - 2020.74x slower +11.52 ms
10 added, 10 removed, 10 edited            31.51 - 5563.72x slower +31.73 ms
1% added, 1% removed, 1% edited            23.07 - 7598.31x slower +43.34 ms
100% modules added                          9.22 - 19017.66x slower +108.48 ms
100% modules removed                        0.91 - 193459.06x slower +1103.56 ms
33% added, 33% removed, 34% edited          0.85 - 206539.74x slower +1178.18 ms
100% modules edited                         0.35 - 506067.89x slower +2886.80 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1        1.32 M      755.71 ns    ±56.58%         667 ns     1781.92 ns
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2       26.37 K       37.92 μs     ±5.83%       37.54 μs       50.94 μs
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
1 vertex        1279.22 K        0.78 μs    ±62.41%        0.63 μs        2.62 μs
8 vertices       875.91 K        1.14 μs    ±34.62%        1.04 μs        2.58 μs
4 vertices       710.20 K        1.41 μs    ±36.67%        1.38 μs        2.71 μs
16 vertices      574.71 K        1.74 μs    ±35.35%        1.58 μs        4.04 μs
32 vertices      421.21 K        2.37 μs    ±27.59%        2.25 μs        5.38 μs
2 vertices       0.0474 K    21116.93 μs     ±1.48%    21092.61 μs    21842.14 μs

Comparison: 
1 vertex        1279.22 K
8 vertices       875.91 K - 1.46x slower +0.36 μs
4 vertices       710.20 K - 1.80x slower +0.63 μs
16 vertices      574.71 K - 2.23x slower +0.96 μs
32 vertices      421.21 K - 3.04x slower +1.59 μs
2 vertices       0.0474 K - 27013.27x slower +21116.15 μs
```


### ✅ compiler » create_page_entry_files_4

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/4          1.61      622.23 ms     ±0.50%      621.92 ms      628.08 ms
```


### ✅ compiler » create_runtime_entry_file_3

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/3         23.27       42.98 ms     ±4.45%       43.05 ms       47.70 ms
```


### ✅ compiler » diff_module_digest_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                      4.40 K      227.46 μs     ±6.41%      227.50 μs      274.48 μs
100% modules added                        3.55 K      281.96 μs    ±10.90%      267.71 μs      392.90 μs
33% added, 33% removed, 34% edited        2.66 K      376.13 μs     ±9.06%      379.83 μs      480.31 μs
1 module added                            1.81 K      552.12 μs     ±4.20%      547.69 μs      636.12 μs
1 added, 1 removed, 1 edited              1.81 K      553.09 μs     ±9.30%      547.38 μs      645.05 μs
no module changes                         1.76 K      566.94 μs     ±4.77%      564.50 μs      664.79 μs
1 module edited                           1.76 K      567.10 μs     ±4.20%      563.67 μs      652.24 μs
1% added, 1% removed, 1% edited           1.76 K      567.97 μs     ±4.20%      564.71 μs      650.63 μs
10 added, 10 removed, 10 edited           1.76 K      568.16 μs     ±4.42%      563.50 μs      659.25 μs
1 module removed                          1.75 K      571.48 μs     ±4.16%      567.17 μs      655.01 μs
3 added, 3 removed, 3 edited              1.74 K      573.50 μs     ±4.52%      567.63 μs      668.83 μs
100% modules edited                       1.69 K      590.07 μs     ±5.81%      586.88 μs      748.11 μs

Comparison: 
100% modules removed                      4.40 K
100% modules added                        3.55 K - 1.24x slower +54.50 μs
33% added, 33% removed, 34% edited        2.66 K - 1.65x slower +148.67 μs
1 module added                            1.81 K - 2.43x slower +324.66 μs
1 added, 1 removed, 1 edited              1.81 K - 2.43x slower +325.63 μs
no module changes                         1.76 K - 2.49x slower +339.48 μs
1 module edited                           1.76 K - 2.49x slower +339.64 μs
1% added, 1% removed, 1% edited           1.76 K - 2.50x slower +340.51 μs
10 added, 10 removed, 10 edited           1.76 K - 2.50x slower +340.70 μs
1 module removed                          1.75 K - 2.51x slower +344.02 μs
3 added, 3 removed, 3 edited              1.74 K - 2.52x slower +346.04 μs
100% modules edited                       1.69 K - 2.59x slower +362.61 μs
```


### ✅ compiler » format_files_2

```
Name                     ips        average  deviation         median         99th %
format_files/2          1.20      836.66 ms     ±1.19%      841.64 ms      849.16 ms
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install       14.65 K      0.00007 s   ±163.27%      0.00006 s      0.00010 s
do install     0.00009 K        10.60 s     ±0.00%        10.60 s        10.60 s

Comparison: 
no install       14.65 K
do install     0.00009 K - 155348.46x slower +10.60 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      207.62 K     0.00482 ms   ±140.05%     0.00458 ms     0.00917 ms
do load      0.0156 K       63.96 ms     ±2.01%       63.45 ms       69.98 ms

Comparison: 
no load      207.62 K
do load      0.0156 K - 13279.56x slower +63.96 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load      107.73 K     0.00928 ms    ±85.74%     0.00887 ms      0.0151 ms
do load     0.00216 K      462.18 ms     ±1.65%      462.87 ms      476.42 ms

Comparison: 
no load      107.73 K
do load     0.00216 K - 49792.62x slower +462.17 ms
```


### ✅ compiler » maybe_load_module_digest_plt_1

```
Name              ips        average  deviation         median         99th %
no load      104.17 K        9.60 μs    ±61.59%        9.17 μs       16.38 μs
do load        2.15 K      464.57 μs     ±3.56%      461.08 μs      546.05 μs

Comparison: 
no load      104.17 K
do load        2.15 K - 48.40x slower +454.97 μs
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1      160.21 K        6.24 μs   ±144.22%        6.13 μs        7.04 μs
```


### ✅ mix » tasks » compile » hologram

```
Name                ips        average  deviation         median         99th %
has cache          0.52         1.93 s     ±1.61%         1.94 s         1.96 s
no cache           0.21         4.70 s     ±0.16%         4.70 s         4.71 s

Comparison: 
has cache          0.52
no cache           0.21 - 2.43x slower +2.77 s
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            28.30 M       35.34 ns  ±5131.00%          42 ns          42 ns
is atom                 9.31 M      107.42 ns ±42993.73%          42 ns         125 ns
is Erlang module        9.07 M      110.27 ns ±43920.87%          42 ns         125 ns
is Elixir module        7.42 M      134.85 ns ±37333.91%          83 ns         166 ns

Comparison: 
is not atom            28.30 M
is atom                 9.31 M - 3.04x slower +72.08 ns
is Erlang module        9.07 M - 3.12x slower +74.94 ns
is Elixir module        7.42 M - 3.82x slower +99.51 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            28.00 M       35.71 ns  ±5186.67%          42 ns          42 ns
is Elixir module        9.40 M      106.34 ns ±37649.41%          83 ns          84 ns
is Erlang module        5.54 M      180.45 ns ±28709.51%          83 ns         125 ns
is atom               0.0756 M    13219.28 ns    ±89.03%       12958 ns       19125 ns

Comparison: 
is not atom            28.00 M
is Elixir module        9.40 M - 2.98x slower +70.64 ns
is Erlang module        5.54 M - 5.05x slower +144.74 ns
is atom               0.0756 M - 370.20x slower +13183.58 ns
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3       15.74 M       63.54 ns ±55022.22%          42 ns          83 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1       12.04 M       83.06 ns ±46403.24%          42 ns          84 ns
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         50.99       19.61 ms     ±4.15%       19.63 ms       21.35 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         50.03       19.99 ms     ±5.32%       20.17 ms       22.14 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        163.73        6.11 ms   ±867.77%        3.38 ms       10.01 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           157.58 M        6.35 ns ±31803.77%        4.20 ns       12.50 ns
is Erlang module       16.88 M       59.24 ns ±50680.37%          42 ns          42 ns
is Elixir module       16.47 M       60.72 ns ±57235.49%          42 ns          42 ns
is atom               0.0746 M    13405.74 ns    ±46.68%       12917 ns       21334 ns

Comparison: 
is not atom           157.58 M
is Erlang module       16.88 M - 9.33x slower +52.89 ns
is Elixir module       16.47 M - 9.57x slower +54.37 ns
is atom               0.0746 M - 2112.44x slower +13399.40 ns
```

