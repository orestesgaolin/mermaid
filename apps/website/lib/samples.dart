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
  Sample('quadrant', 'Quadrant', '''
quadrantChart
    title Reach and engagement
    x-axis Low Reach --> High Reach
    y-axis Low Engagement --> High Engagement
    quadrant-1 Expand
    quadrant-2 Promote
    quadrant-3 Re-evaluate
    quadrant-4 Improve
    Campaign A: [0.3, 0.6]
    Campaign B: [0.45, 0.23]
    Campaign C: [0.78, 0.34]
'''),
  Sample('journey', 'Journey', '''
journey
    title My working day
    section Go to work
      Make tea: 5: Me
      Go upstairs: 3: Me
      Do work: 1: Me, Cat
    section Go home
      Sit down: 5: Me
'''),
  Sample('timeline', 'Timeline', '''
timeline
    title History of Social Media
    section Web 1.0
    2002 : LinkedIn
    2004 : Facebook : Google
    section Web 2.0
    2005 : YouTube
    2006 : Twitter
'''),
  Sample('xychart', 'XY chart', '''
xychart-beta
    title "Sales Revenue"
    x-axis [jan, feb, mar, apr, may, jun]
    y-axis "Revenue (thousands)" 4000 --> 11000
    bar [5000, 6000, 7500, 8200, 9500, 10500]
    line [5000, 6000, 7500, 8200, 9500, 10500]
'''),
  Sample('mindmap', 'Mindmap', '''
mindmap
  root((mermaid))
    Origins
      Long history
      Popularisation
    Research
      On effectiveness
      On features
    Tools
      Pen and paper
      Mermaid
'''),
  Sample('requirement', 'Requirement', '''
requirementDiagram
    requirement test_req {
        id: 1
        text: the test text.
        risk: high
        verifymethod: test
    }
    element test_entity {
        type: simulation
    }
    test_entity - satisfies -> test_req
'''),
  Sample('c4', 'C4', '''
C4Context
    title System Context diagram
    Person(customer, "Banking Customer", "A customer of the bank")
    Enterprise_Boundary(b0, "Bank") {
        System(banking, "Internet Banking", "Allows customers to view accounts")
        SystemDb_Ext(mainframe, "Mainframe", "Stores core banking records")
    }
    Rel(customer, banking, "Uses")
    BiRel(banking, mainframe, "Reads & writes")
'''),
  Sample('dark', 'Dark theme', '''
%%{init: {'theme': 'dark'}}%%
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E((Done))
'''),
  Sample('forest', 'Forest theme', '''
%%{init: {'theme': 'forest'}}%%
graph LR
    seed([Seed]) --> sprout[Sprout]
    sprout --> tree{Healthy?}
    tree -->|yes| forest[[Forest]]
    tree -->|no| compost[(Compost)]
    subgraph Garden
        sprout
        tree
    end
'''),
  Sample('custom', 'Custom colors', '''
%%{init: {"theme": "base", "themeVariables": {
    "primaryColor": "#ffd9e8",
    "primaryBorderColor": "#c2185b",
    "primaryTextColor": "#4a0e2a",
    "lineColor": "#7b1fa2",
    "clusterBkg": "#f3e5f5",
    "clusterBorder": "#9c27b0",
    "edgeLabelBackground": "#fce4ec"
}}}%%
graph TD
    A[Custom themed] -->|styled edge| B(Rounded)
    B --> C{Decision}
    subgraph Cluster
        C -->|yes| D[Yep]
        C -->|no| E[Nope]
    end
'''),
  Sample('styled', 'classDef styles', '''
graph TD
    classDef hot fill:#ffcccc,stroke:#cc0000,stroke-width:2px,color:#660000
    classDef cool fill:#cce5ff,stroke:#0055aa,color:#003366
    A[Normal node] --> B[Hot node]:::hot
    A --> C[Cool node]:::cool
    B --> D{Decision}
    C --> D
    style A fill:#ffffcc,stroke:#aaaa00,stroke-width:3px
    linkStyle 1 stroke:#cc0000,stroke-width:3px
'''),
];
