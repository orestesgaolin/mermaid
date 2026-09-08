/// Deterministic, moderately complex graphs for the ELK demo page.
library;

import 'package:elk/elk.dart';

/// An unrendered ELK example. The page owns layout and presentation.
class ElkStressExample {
  const ElkStressExample({
    required this.title,
    required this.description,
    required this.graph,
    required this.labels,
    this.wide = false,
    this.comparisonNote,
    this.trackingIssue,
  });

  final String title;
  final String description;
  final ElkGraph graph;
  final Map<String, String> labels;
  final bool wide;
  final String? comparisonNote;
  final int? trackingIssue;
}

/// Graphs chosen to exercise hierarchy, ports, cycles, shared routing, and BK
/// placement while remaining small enough to inspect on the demo page.
const elkStressExamples = <ElkStressExample>[
  ElkStressExample(
    title: 'Nested services in three directions',
    comparisonNote:
        'elkjs 0.9.3 ignores child directions under INCLUDE_CHILDREN. '
        'Dart honors the DOWN service group and LEFT worker pool, so this '
        'layout is taller. Broader hierarchy compatibility remains tracked.',
    trackingIssue: 69,
    description:
        'A left-to-right system contains a vertical service group '
        'and a right-to-left worker pool. Cross-boundary edges keep their '
        'endpoint labels through all three coordinate frames.',
    wide: true,
    graph: ElkGraph(
      layoutOptions: ElkLayoutOptions(direction: ElkDirection.right),
      children: [
        ElkNode(id: 'request', width: 104, height: 42),
        ElkNode(
          id: 'platform',
          layoutOptions: ElkLayoutOptions(direction: ElkDirection.down),
          labels: [ElkLabel(text: 'Service platform', width: 100, height: 16)],
          children: [
            ElkNode(id: 'gateway', width: 104, height: 42),
            ElkNode(
              id: 'workers',
              layoutOptions: ElkLayoutOptions(direction: ElkDirection.left),
              labels: [ElkLabel(text: 'Worker pool', width: 100, height: 16)],
              children: [
                ElkNode(id: 'workerA', width: 96, height: 40),
                ElkNode(id: 'queue', width: 88, height: 40),
                ElkNode(id: 'workerB', width: 96, height: 40),
              ],
              edges: [
                ElkEdge(id: 'queueA', sources: ['queue'], targets: ['workerA']),
                ElkEdge(id: 'queueB', sources: ['queue'], targets: ['workerB']),
              ],
            ),
            ElkNode(id: 'cache', width: 92, height: 40),
          ],
          edges: [
            ElkEdge(id: 'dispatch', sources: ['gateway'], targets: ['queue']),
            ElkEdge(id: 'warm', sources: ['cache'], targets: ['workerA']),
          ],
        ),
        ElkNode(id: 'audit', width: 92, height: 40),
        ElkNode(id: 'response', width: 104, height: 42),
      ],
      edges: [
        ElkEdge(id: 'enter', sources: ['request'], targets: ['gateway']),
        ElkEdge(
          id: 'complete',
          sources: ['workerB'],
          targets: ['response'],
          labels: [
            ElkLabel(
              text: 'result',
              width: 34,
              height: 12,
              placement: ElkEdgeLabelPlacement.tail,
            ),
            ElkLabel(
              text: '200',
              width: 22,
              height: 12,
              placement: ElkEdgeLabelPlacement.head,
            ),
          ],
        ),
        ElkEdge(id: 'record', sources: ['gateway'], targets: ['audit']),
        ElkEdge(id: 'publish', sources: ['audit'], targets: ['response']),
      ],
    ),
    labels: {
      'request': 'Request',
      'platform': 'Service platform',
      'gateway': 'API gateway',
      'workers': 'Worker pool',
      'queue': 'Queue',
      'workerA': 'Worker A',
      'workerB': 'Worker B',
      'cache': 'Cache',
      'audit': 'Audit log',
      'response': 'Response',
    },
  ),
  ElkStressExample(
    title: 'Ports, loops, and a message broker',
    trackingIssue: 76,
    comparisonNote:
        'FIXED_SIDE fixes each port side, but permits different '
        'positions and node order. Both engines use the same explicit loop '
        'clearance; alternative arrangements can still be valid.',
    description:
        'Named ports keep publishers and consumers on deliberate '
        'sides. Retry and health loops show route clearance around nodes.',
    wide: true,
    graph: ElkGraph(
      layoutOptions: ElkLayoutOptions(
        direction: ElkDirection.right,
        spacingPortsSurroundingTop: 10,
        spacingPortsSurroundingBottom: 10,
      ),
      children: [
        ElkNode(
          id: 'ingest',
          width: 100,
          height: 54,
          ports: [
            ElkPort(
              id: 'ingestOut',
              side: ElkPortSide.east,
              width: 8,
              height: 8,
            ),
            ElkPort(
              id: 'healthOut',
              side: ElkPortSide.north,
              width: 8,
              height: 8,
            ),
            ElkPort(
              id: 'healthIn',
              side: ElkPortSide.north,
              width: 8,
              height: 8,
            ),
          ],
        ),
        ElkNode(
          id: 'broker',
          width: 126,
          height: 94,
          ports: [
            ElkPort(
              id: 'brokerIn',
              side: ElkPortSide.west,
              width: 8,
              height: 8,
            ),
            ElkPort(
              id: 'ordersOut',
              side: ElkPortSide.east,
              width: 8,
              height: 8,
            ),
            ElkPort(
              id: 'eventsOut',
              side: ElkPortSide.east,
              width: 8,
              height: 8,
            ),
            ElkPort(
              id: 'deadLetter',
              side: ElkPortSide.south,
              width: 8,
              height: 8,
            ),
          ],
        ),
        ElkNode(id: 'orders', width: 106, height: 48),
        ElkNode(id: 'billing', width: 106, height: 48),
        ElkNode(id: 'analytics', width: 106, height: 48),
        ElkNode(id: 'archive', width: 106, height: 48),
        ElkNode(id: 'operator', width: 106, height: 48),
        ElkNode(id: 'status', width: 96, height: 44),
      ],
      edges: [
        ElkEdge(id: 'publish', sources: ['ingestOut'], targets: ['brokerIn']),
        ElkEdge(id: 'ordersFlow', sources: ['ordersOut'], targets: ['orders']),
        ElkEdge(
          id: 'billingFlow',
          sources: ['ordersOut'],
          targets: ['billing'],
        ),
        ElkEdge(
          id: 'metricsFlow',
          sources: ['eventsOut'],
          targets: ['analytics'],
        ),
        ElkEdge(
          id: 'archiveFlow',
          sources: ['eventsOut'],
          targets: ['archive'],
        ),
        ElkEdge(
          id: 'retry',
          sources: ['deadLetter'],
          targets: ['brokerIn'],
          labels: [ElkLabel(text: 'retry', width: 30, height: 12)],
        ),
        ElkEdge(
          id: 'healthLoop',
          sources: ['healthOut'],
          targets: ['healthIn'],
        ),
        ElkEdge(id: 'alert', sources: ['broker'], targets: ['operator']),
        ElkEdge(id: 'dashboard', sources: ['analytics'], targets: ['status']),
      ],
    ),
    labels: {
      'ingest': 'Ingest API',
      'broker': 'Message broker',
      'orders': 'Orders',
      'billing': 'Billing',
      'analytics': 'Analytics',
      'archive': 'Archive',
      'operator': 'Operator',
      'status': 'Status page',
    },
  ),
  ElkStressExample(
    title: 'Cyclic incident workflow',
    description:
        'Feedback paths return failed verification and monitoring '
        'alerts to earlier stages. Cycle breaking restores every arrow after '
        'the layered order is chosen.',
    wide: true,
    graph: ElkGraph(
      layoutOptions: ElkLayoutOptions(
        direction: ElkDirection.right,
        cycleBreaking: ElkCycleBreaking.greedyModelOrder,
      ),
      children: [
        ElkNode(id: 'detect', width: 96, height: 42),
        ElkNode(id: 'triage', width: 96, height: 42),
        ElkNode(id: 'assign', width: 96, height: 42),
        ElkNode(id: 'diagnose', width: 104, height: 42),
        ElkNode(id: 'mitigate', width: 104, height: 42),
        ElkNode(id: 'verify', width: 96, height: 42),
        ElkNode(id: 'monitor', width: 96, height: 42),
        ElkNode(id: 'resolve', width: 96, height: 42),
        ElkNode(id: 'review', width: 96, height: 42),
      ],
      edges: [
        ElkEdge(id: 'd-t', sources: ['detect'], targets: ['triage']),
        ElkEdge(id: 't-a', sources: ['triage'], targets: ['assign']),
        ElkEdge(id: 'a-d', sources: ['assign'], targets: ['diagnose']),
        ElkEdge(id: 'd-m', sources: ['diagnose'], targets: ['mitigate']),
        ElkEdge(id: 'm-v', sources: ['mitigate'], targets: ['verify']),
        ElkEdge(id: 'v-m', sources: ['verify'], targets: ['mitigate']),
        ElkEdge(id: 'v-o', sources: ['verify'], targets: ['monitor']),
        ElkEdge(id: 'o-t', sources: ['monitor'], targets: ['triage']),
        ElkEdge(id: 'o-r', sources: ['monitor'], targets: ['resolve']),
        ElkEdge(id: 'r-p', sources: ['resolve'], targets: ['review']),
        ElkEdge(id: 'p-d', sources: ['review'], targets: ['detect']),
      ],
    ),
    labels: {
      'detect': 'Detect',
      'triage': 'Triage',
      'assign': 'Assign',
      'diagnose': 'Diagnose',
      'mitigate': 'Mitigate',
      'verify': 'Verify',
      'monitor': 'Monitor',
      'resolve': 'Resolve',
      'review': 'Review',
    },
  ),
  ElkStressExample(
    title: 'Shared deployment routes',
    comparisonNote:
        'Release → Production → Telemetry → Rollback → Release is '
        'a cycle, so one edge must run backward. elkjs chooses Production → '
        'Telemetry; Dart chooses Rollback → Release. Follow the arrowheads '
        'to read the same directed sequence in either layout.',
    trackingIssue: 77,
    description:
        'Three build sources fan into one release hub, then share '
        'outgoing trunks to four environments. Junctions expose the merged '
        'route structure.',
    wide: true,
    graph: ElkGraph(
      layoutOptions: ElkLayoutOptions(
        direction: ElkDirection.right,
        mergeEdges: true,
      ),
      children: [
        ElkNode(id: 'web', width: 94, height: 42),
        ElkNode(id: 'api', width: 94, height: 42),
        ElkNode(id: 'worker', width: 94, height: 42),
        ElkNode(id: 'release', width: 112, height: 58),
        ElkNode(id: 'dev', width: 110, height: 42),
        ElkNode(id: 'staging', width: 110, height: 42),
        ElkNode(id: 'canary', width: 88, height: 42),
        ElkNode(id: 'prod', width: 88, height: 42),
        ElkNode(id: 'telemetry', width: 100, height: 42),
        ElkNode(id: 'rollback', width: 100, height: 42),
      ],
      edges: [
        ElkEdge(id: 'bundle-web', sources: ['web'], targets: ['release']),
        ElkEdge(id: 'bundle-api', sources: ['api'], targets: ['release']),
        ElkEdge(id: 'bundle-worker', sources: ['worker'], targets: ['release']),
        ElkEdge(id: 'deploy-dev', sources: ['release'], targets: ['dev']),
        ElkEdge(
          id: 'deploy-staging',
          sources: ['release'],
          targets: ['staging'],
        ),
        ElkEdge(id: 'deploy-canary', sources: ['release'], targets: ['canary']),
        ElkEdge(id: 'deploy-prod', sources: ['release'], targets: ['prod']),
        ElkEdge(id: 'observe', sources: ['prod'], targets: ['telemetry']),
        ElkEdge(id: 'revert', sources: ['telemetry'], targets: ['rollback']),
        ElkEdge(
          id: 'retryRelease',
          sources: ['rollback'],
          targets: ['release'],
        ),
      ],
    ),
    labels: {
      'web': 'Web build',
      'api': 'API build',
      'worker': 'Worker build',
      'release': 'Release hub',
      'dev': 'Development',
      'staging': 'Staging',
      'canary': 'Canary',
      'prod': 'Production',
      'telemetry': 'Telemetry',
      'rollback': 'Rollback',
    },
  ),
  ElkStressExample(
    title: 'BK alignment: upper sweep',
    description:
        'LEFTUP fixes the Brandes-Kopf sweep to its upper alignment. '
        'Compare the vertical lanes with the balanced variant.',
    wide: true,
    graph: ElkGraph(
      layoutOptions: ElkLayoutOptions(
        direction: ElkDirection.right,
        fixedAlignment: ElkFixedAlignment.leftUp,
      ),
      children: _alignmentNodes,
      edges: _alignmentEdges,
    ),
    labels: _alignmentLabels,
  ),
  ElkStressExample(
    title: 'BK alignment: balanced',
    description:
        'BALANCED combines all four BK sweeps for the same graph and '
        'input order, producing a different but still overlap-free layout.',
    wide: true,
    graph: ElkGraph(
      layoutOptions: ElkLayoutOptions(
        direction: ElkDirection.right,
        fixedAlignment: ElkFixedAlignment.balanced,
      ),
      children: _alignmentNodes,
      edges: _alignmentEdges,
    ),
    labels: _alignmentLabels,
  ),
];

const _alignmentNodes = [
  ElkNode(id: 'idea', width: 88, height: 40),
  ElkNode(id: 'ux', width: 102, height: 46),
  ElkNode(id: 'apiDesign', width: 102, height: 42),
  ElkNode(id: 'mobile', width: 110, height: 54),
  ElkNode(id: 'backend', width: 110, height: 48),
  ElkNode(id: 'qa', width: 92, height: 42),
  ElkNode(id: 'security', width: 100, height: 46),
  ElkNode(id: 'ship', width: 88, height: 48),
];

const _alignmentEdges = [
  ElkEdge(id: 'idea-ux', sources: ['idea'], targets: ['ux']),
  ElkEdge(id: 'idea-api', sources: ['idea'], targets: ['apiDesign']),
  ElkEdge(id: 'ux-mobile', sources: ['ux'], targets: ['mobile']),
  ElkEdge(id: 'api-mobile', sources: ['apiDesign'], targets: ['mobile']),
  ElkEdge(id: 'api-backend', sources: ['apiDesign'], targets: ['backend']),
  ElkEdge(id: 'mobile-qa', sources: ['mobile'], targets: ['qa']),
  ElkEdge(id: 'backend-qa', sources: ['backend'], targets: ['qa']),
  ElkEdge(id: 'backend-security', sources: ['backend'], targets: ['security']),
  ElkEdge(id: 'qa-ship', sources: ['qa'], targets: ['ship']),
  ElkEdge(id: 'security-ship', sources: ['security'], targets: ['ship']),
];

const _alignmentLabels = {
  'idea': 'Product idea',
  'ux': 'UX design',
  'apiDesign': 'API design',
  'mobile': 'Mobile app',
  'backend': 'Backend',
  'qa': 'QA',
  'security': 'Security',
  'ship': 'Release',
};
