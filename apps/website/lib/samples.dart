/// Comparison samples — one per supported diagram type.
library;

class Sample {
  const Sample(this.id, this.name, this.source);

  final String id;
  final String name;
  final String source;
}

const samples = <Sample>[
  Sample('flowchart', 'Flowchart', '''
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E[Celebrate]
'''),
  Sample('subgraphs', 'Subgraphs', '''
graph LR
    subgraph Stage One
        a1[Fetch] --> a2[Validate]
    end
    subgraph Stage Two
        b1[Transform] --> b2[Store]
    end
    a2 --> b1
    Start([Start]) --> a1
    b2 --> Done([Done])
'''),
  Sample('sequence', 'Sequence', '''
sequenceDiagram
    autonumber
    actor U as User
    participant W as Web App
    participant S as Auth Service
    U->>+W: Login request
    W->>+S: Validate credentials
    Note right of S: Check password hash
    alt valid
        S-->>W: Token
        W-->>U: Welcome!
    else invalid
        S-->>-W: 401
        W-->>-U: Try again
    end
'''),
  Sample('class', 'Class', '''
classDiagram
    class Animal {
        <<abstract>>
        +String name
        +isMammal() bool
        +mate()*
    }
    Animal <|-- Duck
    Animal <|-- Fish
    Duck "1" --> "*" Egg : lays
'''),
  Sample('state', 'State', '''
stateDiagram-v2
    [*] --> Idle
    Idle --> Connecting : connect
    state check <<choice>>
    Connecting --> check
    check --> Connected : ok
    check --> Backoff : failed
    Backoff --> Connecting : retry
    Connected --> [*]
'''),
  Sample('er', 'ER', '''
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    CUSTOMER {
        string name PK
        string email UK
    }
'''),
  Sample('gantt', 'Gantt', '''
gantt
    dateFormat YYYY-MM-DD
    title Release plan
    section Design
    Wireframes      : done, des1, 2024-03-01, 4d
    Visual design   : active, des2, after des1, 5d
    section Build
    API             : crit, api1, 2024-03-04, 7d
    Frontend        : fe1, after des2, 6d
'''),
  Sample('pie', 'Pie', '''
pie showData title Browser share
    "Chrome" : 64.7
    "Safari" : 18.1
    "Edge" : 5.4
    "Other" : 11.8
'''),
];
