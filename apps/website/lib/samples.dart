/// Comparison samples — one per supported diagram type, grouped into
/// categories and annotated with a short "what it is / when to use it"
/// description so the page reads like documentation.
library;

class Sample {
  const Sample(this.id, this.name, this.category, this.description,
      this.source);

  final String id;
  final String name;

  /// Grouping shown as a section heading on the page.
  final String category;

  /// One-line explanation of the diagram type and when to reach for it.
  final String description;
  final String source;
}

const cDiagrams = 'Diagrams';
const cCharts = 'Charts & data';
const cTheming = 'Theming & styles';

const samples = <Sample>[
  Sample('flowchart', 'Flowchart', cDiagrams,
      'Nodes connected by edges for processes, decisions and flows — the '
          'most common Mermaid diagram.', '''
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E[Celebrate]
'''),
  Sample('subgraphs', 'Subgraphs', cDiagrams,
      'Group related nodes into labelled clusters; edges can cross freely '
          'between them.', '''
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
  Sample('sequence', 'Sequence', cDiagrams,
      'Interactions between participants over time: messages, activations '
          'and alt/opt blocks.', '''
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
  Sample('class', 'Class', cDiagrams,
      'UML class diagrams: classes, members, visibility markers and '
          'relationships.', '''
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
  Sample('state', 'State', cDiagrams,
      'Finite state machines: states, transitions, choice nodes and '
          'start/end markers.', '''
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
  Sample('er', 'ER', cDiagrams,
      'Entity-relationship diagrams: entities, attributes and the '
          'cardinality between them.', '''
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    CUSTOMER {
        string name PK
        string email UK
    }
'''),
  Sample('icons', 'Icons', cDiagrams,
      'Iconify-style icons on flowchart nodes via `@{ icon: "pack:name" }`. '
          '(mermaid.js needs the same pack registered to show them.)', '''
flowchart LR
    A@{ icon: "icon:cloud", label: "Cloud" } --> B@{ icon: "icon:database", label: "Store" }
    B --> C@{ icon: "icon:cog", label: "Process" }
    C --> D@{ icon: "icon:star", label: "Done" }
'''),
  Sample('math', 'Math', cDiagrams,
      'LaTeX math in node and edge labels with `\$\$...\$\$` — fractions, '
          'roots, arrays, sized delimiters, vectors and a full symbol table, '
          'all laid out as scene primitives (no webview).', r'''
graph TD
    Q["$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$"]
    S["$$i\hbar\frac{\partial}{\partial t}\Psi = -\frac{\hbar}{2m}\nabla^2\Psi + V\Psi$$"]
    M["$$\left\{ \begin{array}{l} \nabla\cdot\vec{E} = \rho \\ \nabla\times\vec{B} = \vec{J} \end{array} \right.$$"]
    Q --> S --> M
'''),
  Sample('git', 'Git graph', cDiagrams,
      'Git branching and merging visualised as commits flowing across '
          'branches over time.', '''
gitGraph
   commit
   commit id: "Normal" tag: "v1.0.0"
   branch develop
   checkout develop
   commit
   commit
   checkout main
   merge develop
   commit type: HIGHLIGHT
   commit type: REVERSE
'''),
  Sample('requirement', 'Requirement', cDiagrams,
      'Requirements with their attributes, and how elements satisfy or '
          'verify them.', '''
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
  Sample('c4', 'C4', cDiagrams,
      'C4-model context diagrams: people, systems, boundaries and their '
          'relationships.', '''
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
  Sample('block', 'Block', cDiagrams,
      'Grid-based blocks laid out in columns, with nested groups and edges '
          'between them.', '''
block-beta
    columns 3
    A["Input"] B["Process"] C["Output"]
    block:group:3
        D["Worker 1"] E["Worker 2"]
    end
    A --> B
'''),
  Sample('architecture', 'Architecture', cDiagrams,
      'Cloud/service architecture: grouped services (databases, servers, '
          'disks) wired together with directional edges.', '''
architecture-beta
    group api(cloud)[API]
    service db(database)[Database] in api
    service server(server)[Server] in api
    service disk(disk)[Storage] in api
    db:L -- R:server
    server:L -- R:disk
'''),
  Sample('kanban', 'Kanban', cDiagrams,
      'Task board with columns; each column lists its cards top to bottom.',
      '''
kanban
    todo[To Do]
        t1[Design API]
        t2[Write specs]
    doing[In Progress]
        t3[Build UI]
    done[Done]
        t4[Setup repo]
        t5[CI pipeline]
'''),
  Sample('cynefin', 'Cynefin', cDiagrams,
      'Cynefin sense-making framework: items sorted across the clear, '
          'complicated, complex and chaotic domains.', '''
cynefin-beta
    title Decision contexts
    clear
        Run a backup
    complicated
        Tune the database
    complex
        Launch a new product
    chaotic
        Recover from outage
'''),
  Sample('ishikawa', 'Ishikawa', cDiagrams,
      'Fishbone (cause-and-effect) diagram: a problem with contributing '
          'causes grouped by category.', '''
ishikawa-beta
    Slow website
        People
            Untrained staff
        Process
            No caching
        Technology
            Old servers
'''),
  Sample('eventmodeling', 'Event modeling', cDiagrams,
      'Event-modeling timeline: UI, commands, events and read models placed '
          'along a horizontal flow.', '''
eventmodeling
    tf 01 ui Order Page
    tf 02 cmd Place Order
    tf 03 evt Order Placed
    tf 04 view Order List
'''),
  Sample('railroad', 'Railroad', cDiagrams,
      'Syntax (railroad) diagram: grammar rules drawn as branching tracks.',
      '''
railroad-diagram
    title Greeting grammar
    name = "a" | "b" ;
'''),
  Sample('pie', 'Pie', cCharts,
      'Proportional slices computed from labelled values, with optional '
          'data labels.', '''
pie showData title Browser share
    "Chrome" : 64.7
    "Safari" : 18.1
    "Edge" : 5.4
    "Other" : 11.8
'''),
  Sample('quadrant', 'Quadrant', cCharts,
      'Plot items across two axes into four labelled quadrants for '
          'prioritisation.', '''
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
  Sample('xychart', 'XY chart', cCharts,
      'Bar and line series plotted over a shared category axis.', '''
xychart-beta
    title "Sales Revenue"
    x-axis [jan, feb, mar, apr, may, jun]
    y-axis "Revenue (thousands)" 4000 --> 11000
    bar [5000, 6000, 7500, 8200, 9500, 10500]
    line [5000, 6000, 7500, 8200, 9500, 10500]
'''),
  Sample('gantt', 'Gantt', cCharts,
      'Project schedule: tasks, sections, dependencies and milestones laid '
          'out over dates.', '''
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
  Sample('journey', 'Journey', cCharts,
      'User-journey stages scored by satisfaction and grouped into '
          'sections.', '''
journey
    title My working day
    section Go to work
      Make tea: 5: Me
      Go upstairs: 3: Me
      Do work: 1: Me, Cat
    section Go home
      Sit down: 5: Me
'''),
  Sample('timeline', 'Timeline', cCharts,
      'Chronological events grouped into time periods.', '''
timeline
    title History of Social Media
    section Web 1.0
    2002 : LinkedIn
    2004 : Facebook : Google
    section Web 2.0
    2005 : YouTube
    2006 : Twitter
'''),
  Sample('sankey', 'Sankey', cCharts,
      'Flow diagram: nodes in layered columns, links drawn as ribbons whose '
          'width is proportional to the flow value.', '''
sankey-beta
Coal,Electricity,40
Gas,Electricity,25
Solar,Electricity,10
Electricity,Homes,35
Electricity,Industry,30
Electricity,Losses,10
'''),
  Sample('packet', 'Packet', cCharts,
      'Network-packet layout: bit ranges as labelled blocks on a 32-bit grid '
          'with bit-index markers.', '''
packet
0-15: "Source Port"
16-31: "Destination Port"
32-63: "Sequence Number"
64-95: "Acknowledgment Number"
96-99: "Data Offset"
100-105: "Reserved"
106: "URG"
107: "ACK"
108: "PSH"
109: "RST"
110: "SYN"
111: "FIN"
112-127: "Window"
'''),
  Sample('mindmap', 'Mindmap', cCharts,
      'Hierarchical ideas radiating outward from a central root.', '''
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
  Sample('radar', 'Radar', cCharts,
      'Radar (spider) chart: one or more series plotted across shared axes '
          'radiating from a centre.', '''
radar-beta
    title Skills
    axis design, code, comms, testing, ops
    curve alice{4, 5, 3, 4, 2}
    curve bob{3, 4, 5, 2, 4}
    max 5
    min 0
'''),
  Sample('treemap', 'Treemap', cCharts,
      'Nested rectangles sized by value, grouped into categories.', '''
treemap-beta
    "Frontend"
        "UI": 40
        "State": 25
    "Backend"
        "API": 35
        "DB": 20
'''),
  Sample('venn', 'Venn', cCharts,
      'Overlapping sets with their intersections and unions highlighted.', '''
venn-beta
    title Skills overlap
    set frontend ["UI", "CSS"]
    set backend ["API", "DB"]
    union ["frontend", "backend"]
'''),
  Sample('wardley', 'Wardley map', cCharts,
      'Value-chain map: components placed by visibility and evolution, with '
          'dependencies and an expected movement.', '''
wardley-beta
    title Tea shop
    component Cup [0.9, 0.6]
    component Tea [0.7, 0.7]
    component Kettle [0.5, 0.4]
    Cup -> Tea
    Tea -> Kettle
    evolve Kettle 0.8
'''),
  Sample('dark', 'Dark theme', cTheming,
      'The same flowchart with the built-in dark theme, selected via an '
          '%%{init}%% directive.', '''
%%{init: {'theme': 'dark'}}%%
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E((Done))
'''),
  Sample('forest', 'Forest theme', cTheming,
      'The forest theme — a green palette — applied through a directive.', '''
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
  Sample('custom', 'Custom colors', cTheming,
      'Override individual theme variables (primaryColor, lineColor…) with '
          'themeVariables.', '''
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
  Sample('handdrawn', 'Hand-drawn', cTheming,
      'The sketchy `look: handDrawn` style — wobbly double-stroked borders '
          'and hachure fills, seeded for stable output.', '''
%%{init: {'look': 'handDrawn'}}%%
graph TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E[Celebrate]
'''),
  Sample('styled', 'classDef styles', cTheming,
      'Per-node classDef classes, inline style, and linkStyle on a specific '
          'edge.', '''
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

/// Categories in display order.
const sampleCategories = <String>[cDiagrams, cCharts, cTheming];
