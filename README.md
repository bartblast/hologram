# Hologram

## Roadmap

:white_check_mark:&nbsp;&nbsp;==&nbsp;&nbsp;DONE

:construction:&nbsp;&nbsp;==&nbsp;&nbsp;IN PROGRESS (partially done, some features work)

:x:&nbsp;&nbsp;==&nbsp;&nbsp;TODO

### Runtime

#### Core

| Feature     | Status             |
| :---------- | :----------------: |
| Actions     | :white_check_mark: |
| Commands    | :white_check_mark: |
| Routing     | :x:                |
| Session     | :x:                |

#### Template Engine

| Feature         | Status             | Comments                                                        |
| :-------------- | :----------------: | :-------------------------------------------------------------- |
| Components      | :x:                |                                                                 |
| If Directive    | :construction:     | done: element nodes, todo: component nodes                      |
| Interpolation   | :x:                |                                                                 |
| Layouts         | :x:                |                                                                 |
| Navigation      | :construction:     |                                                                 |
| Pages           | :x:                |                                                                 |
| Templates       | :x:                |                                                                 |
| Two-Way Binding | :x:                |                                                                 |

#### Events

| Event        | Status             | Comments                                                        |
| :----------- | :----------------: | :-------------------------------------------------------------- |
| Blur         | :white_check_mark: |                                                                 |
| Change       | :construction:     | done: form tags, todo: input, select, textarea tags             |
| Click        | :construction:     | done: event handling, todo: event metadata                      |
| Focus        | :x:                |                                                                 |
| Key Down     | :x:                |                                                                 |
| Key Press    | :x:                |                                                                 |
| Key Up       | :x:                |                                                                 |
| Mouse Move   | :x:                |                                                                 |
| Params       | :x:                |                                                                 |
| Resize       | :x:                |                                                                 |
| Scroll       | :x:                |                                                                 |
| Select       | :x:                |                                                                 |
| Submit       | :white_check_mark: |                                                                 |
| Tap          | :x:                |                                                                 |
| Target       | :x:                |                                                                 |
| Touch Cancel | :x:                |                                                                 |
| Touch End    | :x:                |                                                                 |
| Touch Move   | :x:                |                                                                 |
| Touch Start  | :x:                |                                                                 |

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
| Atom               | :x:                |
| Binary             | :x:                |
| Bitstring          | :x:                |     
| Boolean            | :x:                |     
| Exception          | :x:                |     
| Float              | :x:                |     
| Integer            | :x:                |     
| IO Data            | :x:                |     
| List               | :x:                |     
| Map                | :x:                |     
| Nil                | :x:                |    
| Range              | :x:                |     
| Regex              | :x:                |     
| String             | :x:                |     
| Struct             | :x:                |     
| Tuple              | :x:                |     

#### Operators

##### Overridable General Operators

| Operator | Status             |
| :------- | :----------------: |
| unary +  | :x:                |
| unary -  | :x:                |
| +        | :x:                |
| -        | :x:                |
| *        | :x:                |
| /        | :x:                |
| ++       | :x:                |
| --       | :x:                |
| and      | :x:                |
| &&       | :x:                |
| or       | :x:                |
| \|\|     | :x:                |
| not      | :x:                |
| !        | :x:                |
| in       | :x:                |
| not in   | :x:                |
| @        | :x:                |
| ..       | :x:                |
| <>       | :x:                |
| \|>      | :x:                |
| =~       | :x:                |

##### Non-Overridable General Operators

| Operator | Status             |
| :------- | :----------------: |
| ^        | :x:                |
| .        | :x:                |
| =        | :x:                |
| &        | :x:                |
| ::       | :x:                |

##### Comparison Operators

| Operator | Status             |
| :------- | :----------------: |
| ==       | :x:                |
| ===      | :x:                |
| !=       | :x:                |
| !==      | :x:                |
| <        | :x:                |
| >        | :x:                |
| <=       | :x:                |
| =>       | :x:                |

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
| Map           | :x:                |       
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
| Else (If)     | :x:                |
| Else (Rescue) | :x:                |
| Guards        | :x:                |
| If            | :x:                |
| Raise         | :x:                |
| Rescue        | :x:                |
| Throw         | :x:                |
| Unless        | :x:                |
| With          | :x:                |

#### Definitions

| Structure        | Status             |
| :--------------- | :----------------: |
| Exception        | :x:                |
| Function Head    | :x:                |
| Macro            | :x:                |
| Module           | :x:                |
| Module Attribute | :x:                |
| Private Function | :x:                |
| Public Function  | :x:                |


#### Directives

| Directive        | Status             |
| :--------------- | :----------------: |
| Alias            | :x:                |
| Import           | :x:                |
| Multi-Alias      | :x:                |
| Require          | :x:                |
| Use              | :x:                |

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
| Module \_\_info\_\_/1 callback | :x:                |
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