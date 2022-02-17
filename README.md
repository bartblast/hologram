# Hologram

Full stack isomorphic Elixir web framework.

## Roadmap

:white_check_mark:&nbsp;&nbsp;==&nbsp;&nbsp;DONE

:construction:&nbsp;&nbsp;==&nbsp;&nbsp;IN PROGRESS (partially done, some features work)

:x:&nbsp;&nbsp;==&nbsp;&nbsp;TODO

### Runtime

#### Core

| Feature     | Status             | Comments                                                        |
| :---------- | :----------------: | :-------------------------------------------------------------- |
| Actions     | :white_check_mark: |                                                                 |
| Commands    | :white_check_mark: |                                                                 |
| Routing     | :construction:     | done: paths without params, todo: params                        |
| Session     | :x:                |                                                                 |

#### Template Engine

| Feature         | Status             | Comments                                                        |
| :-------------- | :----------------: | :-------------------------------------------------------------- |
| Components      | :construction:     | done: stateless/stateful components, todo: props DSL            |
| If Directive    | :construction:     | done: element nodes, todo: component nodes                      |
| Interpolation   | :white_check_mark: |                                                                 |
| Layouts         | :white_check_mark: |                                                                 |
| Navigation      | :white_check_mark: |                                                                 |
| Pages           | :white_check_mark: |                                                                 |
| Templates       | :construction:     | done: template in module, todo: template in separate file       |
| Two-Way Binding | :x:                |                                                                 |

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

| Tool           | Status             |
| :------------- | :----------------: |
| Authentication | :x:                |
| Authorization  | :x:                |
| Caching        | :x:                |
| Code Reload    | :x:                |
| Localization   | :x:                |
| Time Travel    | :x:                |

### Elixir Syntax

#### Types

| Type               | Status             |
| :----------------- | :----------------: |
| Anonymous Function | :x:                |
| Atom               | :white_check_mark: |
| Binary             | :x:                |
| Bitstring          | :x:                |     
| Boolean            | :white_check_mark: |     
| Exception          | :x:                |     
| Float              | :white_check_mark: |     
| Integer            | :white_check_mark: |     
| IO Data            | :x:                |     
| List               | :white_check_mark: |     
| Map                | :white_check_mark: |     
| Nil                | :white_check_mark: |    
| Range              | :x:                |     
| Regex              | :x:                |     
| String             | :white_check_mark: |     
| Struct             | :white_check_mark: |   
| Tuple              | :white_check_mark: |     

#### Operators

##### Overridable General Operators

| Operator | Status             |
| :------- | :----------------: |
| unary +  | :x:                |
| unary -  | :white_check_mark: |
| +        | :white_check_mark: |
| -        | :white_check_mark: |
| *        | :white_check_mark: |
| /        | :white_check_mark: |
| ++       | :x:                |
| --       | :x:                |
| and      | :x:                |
| &&       | :white_check_mark: |
| or       | :x:                |
| \|\|     | :x:                |
| not      | :x:                |
| !        | :x:                |
| in       | :x:                |
| not in   | :x:                |
| @        | :white_check_mark: |
| ..       | :x:                |
| <>       | :x:                |
| \|>      | :x:                |
| =~       | :x:                |

##### Non-Overridable General Operators

| Operator | Status             |
| :------- | :----------------: |
| ^        | :x:                |
| .        | :white_check_mark: |
| =        | :white_check_mark: |
| &        | :x:                |
| ::       | :x:                |

##### Comparison Operators

| Operator | Status             |
| :------- | :----------------: |
| ==       | :white_check_mark: |
| ===      | :x:                |
| !=       | :x:                |
| !==      | :x:                |
| <        | :x:                |
| >        | :x:                |
| <=       | :x:                |
| >=       | :x:                |

##### Bitwise Module Operators

| Operator | Status             |
| :------- | :----------------: |
| &&&      | :x:                |
| ^^^      | :x:                |  
| <<<      | :x:                |  
| >>>      | :x:                |  
| \|\|\|   | :x:                |  
| ~~~      | :x:                |

#### Pattern Matching

| Type          | Status             |
| :------------ | :----------------: |
| Binary        | :x:                |
| Bitstring     | :x:                |
| Case          | :x:                |
| Comprehension | :x:                |
| List          | :x:                |
| Map           | :white_check_mark: |      
| Range         | :x:                |          
| Struct        | :x:                |          
| Tuple         | :x:                |          

#### Control Flow

| Structure     | Status             |
| :------------ | :----------------: |
| After         | :x:                |
| Case          | :x:                |
| Catch         | :x:                |
| Comprehension | :x:                |
| Cond          | :x:                |
| Else (If)     | :white_check_mark: |
| Else (Rescue) | :x:                |
| Guards        | :x:                |
| If            | :white_check_mark: |
| Raise         | :x:                |
| Rescue        | :x:                |
| Throw         | :x:                |
| Unless        | :x:                |
| With          | :x:                |

#### Definitions

| Structure        | Status             |
| :--------------- | :----------------: |
| Exception        | :x:                |
| Function Head    | :white_check_mark: |
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

#### Sigils

| Sigil | Status             |
| :---- | :----------------: |
| ~c    | :x:                |
| ~C    | :x:                |
| ~D    | :x:                |
| ~N    | :x:                |
| ~r    | :x:                |
| ~R    | :x:                |
| ~s    | :x:                |
| ~S    | :x:                |
| ~T    | :x:                |
| ~U    | :x:                |
| ~w    | :x:                |
| ~W    | :x:                |

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
* Types: PID, Port, Reference
* Control Flow: Exit, Receive
* Operators: Custom, Overriding
* Other: Erlang Libraries

### Work in progress

#### Runtime / Core / Commands
Done: commands trigerred by action\
Todo: commands trigerred by event