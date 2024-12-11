## Is it used in production?

Yes, it's used in Segmetric: https://www.segmetric.com/. Take a look at the “join beta” and “contact pages" which showcase form handling, or check the mobile menu.
This all works on transpiled Elixir code! (But please, submit the forms only if you actually want to join the Segmetric beta or contact Segmetric - it is a live page, thanks!)

## History / background

I tried to write this kind of framework first in Ruby and managed to create a working prototype, but the performance was not satisfactory.
Then I tried Crystal, but it was very hard to work with its AST. Then I moved to Kotlin, but I realized that it’s better to use a dynamically typed language …
Then I found Elixir in 2018 and fell in love with it. I started work on Hologram in the summer of 2020.

## Roadmap
This is a work in progress (although usable and used in production). To check what works and what is planned - take a look at the roadmap in the readme at [Github bartblast/hologram](https://github.com/bartblast/hologram#readme)

To meet the objective of being a very friendly developer experience, Hologram will provide out-of-the-box such things as UI component library (CSS framework agnostic),
authentication, authorization, easy debugging (with time travel), caching, localization and some other features that you typically use in a web app.

I believe that using Hologram’s approach, i.e. Elixir-JS transpilation, code on client and action/command architecture it will be possible to create something as productive as Rails,
without its shortcomings related to scalability, efficiency, etc.

:white_check_mark:&nbsp;&nbsp;==&nbsp;&nbsp;DONE

:construction:&nbsp;&nbsp;==&nbsp;&nbsp;IN PROGRESS (partially done, some features work)

:x:&nbsp;&nbsp;==&nbsp;&nbsp;TODO

### Runtime

#### Template Engine

| Feature         | Status             | Comments                                                        |
| :-------------- | :----------------: | :-------------------------------------------------------------- |
| Pages           | :white_check_mark: |                                                                 |
| Templates       | :construction:     | done: template in module, todo: template in separate file       |

#### Events

| Event          | Status             | Comments                                                        |
| :------------- | :----------------: | :-------------------------------------------------------------- |
| Blur           | :white_check_mark: |                                                                 |
| Change         | :construction:     | done: form tags, todo: input, select, textarea tags             |
| Click          | :construction:     | done: event handling, todo: event metadata                      |
| Click Away     | :x:                |                                                                 |
| Focus          | :x:                |                                                                 |
| Key Down       | :x:                |                                                                 |
| Key Press      | :x:                |                                                                 |
| Key Up         | :x:                |                                                                 |
| Mouse Move     | :x:                |                                                                 |
| Params         | :x:                |                                                                 |
| Pointer Down   | :construction:     | done: event handling, todo: event metadata                      |
| Pointer Up     | :construction:     | done: event handling, todo: event metadata                      |
| Resize         | :x:                |                                                                 |
| Scroll         | :x:                |                                                                 |
| Select         | :x:                |                                                                 |
| Submit         | :white_check_mark: |                                                                 |
| Tap            | :x:                |                                                                 |
| Target         | :x:                |                                                                 |
| Touch Cancel   | :x:                |                                                                 |
| Touch End      | :x:                |                                                                 |
| Touch Move     | :x:                |                                                                 |
| Touch Start    | :x:                |                                                                 |
| Transition End | :white_check_mark: |                                                                 |

#### Tools

| Tool           | Status             | Comments                                                        |
| :------------- | :----------------: | :-------------------------------------------------------------- |
| Authentication | :x:                |                                                                 |
| Authorization  | :x:                |                                                                 |
| Caching        | :x:                |                                                                 |
| Code Reload    | :construction:     | done: recompiling, reloading, todo: incremental compilation     |
| Localization   | :x:                |                                                                 |
| Time Travel    | :x:                |                                                                 |

### Elixir Syntax

#### Pattern Matching

| Type               | Status             |
| :----------------- | :----------------: |
| Anonymous Function | :x:                |
| Binary             | :x:                |
| Bitstring          | :x:                |
| Case               | :white_check_mark: |
| Comprehension      | :white_check_mark: |
| Cons Operator      | :white_check_mark: |
| Module Function    | :white_check_mark: |
| If                 | :x:                |
| List               | :white_check_mark: |
| Map                | :white_check_mark: |      
| Range              | :x:                |          
| Struct             | :x:                |          
| Tuple              | :white_check_mark: |        

#### Definitions

| Structure        | Status             |
| :--------------- | :----------------: |
| Exception        | :x:                |
| Function Head    | :x:                |
| Macro            | :x:                |
| Module           | :white_check_mark: |
| Module Attribute | :white_check_mark: |
| Private Function | :white_check_mark: |
| Public Function  | :white_check_mark: |


#### Directives

| Directive        | Status             |
| :--------------- | :----------------: |
| Alias            | :white_check_mark: |
| Import           | :white_check_mark: |
| Multi-Alias      | :x:                |
| Require          | :white_check_mark: |
| Use              | :white_check_mark: |

#### Other

| Feature                        | Status             |
| :----------------------------- | :----------------: |
| Behaviours                     | :x:                |
| Codepoints                     | :x:                |
| Custom Sigils                  | :x:                |
| Default Arguments              | :x:                |
| Function Capturing             | :x:                |
| Map Update Syntax              | :x:                |
| Module Attribute Accumulation  | :x:                |
| Module \_\_info\_\_/1 callback | :white_check_mark: |
| Module Nesting                 | :x:                |
| Protocols                      | :x:                |
| Variable rebinding             | :x:                |

#### Not on Roadmap
* Control Flow: Exit, Receive