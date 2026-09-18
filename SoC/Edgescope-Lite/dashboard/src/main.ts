import {
  DEMO_SPECS,
  type DemoKey,
  type ValidatedCapture,
} from "./app/captureModel";
import { getControlPolicy } from "./app/controlPolicy";
import { DashboardStore, type DashboardState } from "./app/dashboardStore";
import {
  PendingProtocolBridge,
  type ProtocolBridge,
} from "./app/protocolBridge";
import { MockTransport } from "./transport/mockTransport";
import type {
  ConfigurableMockTransport,
  DashboardEvent,
  DashboardTransport,
  MockScenario,
  TransportKind,
} from "./transport/transport";
import { WebSerialTransport } from "./transport/webSerialTransport";
import { DemoPanel } from "./ui/demoPanel";
import { RawLog } from "./ui/rawLog";
import { ValidationPanel } from "./ui/validationPanel";
import { WaveformCanvas, type ViewWindow } from "./ui/waveformCanvas";
import { WorkflowPanel } from "./ui/workflowPanel";

function element<T extends HTMLElement>(id: string): T {
  const found = document.getElementById(id);
  if (found === null) {
    throw new Error(`필수 UI element #${id}를 찾을 수 없습니다.`);
  }
  return found as T;
}

function connectionTone(state: DashboardState["transport"]["state"]): string {
  if (state === "connected") {
    return "status-pill status-pill--connected";
  }
  if (state === "connecting" || state === "disconnecting") {
    return "status-pill status-pill--busy";
  }
  if (state === "error" || state === "unsupported") {
    return "status-pill status-pill--error";
  }
  return "status-pill status-pill--idle";
}

function firmwareTone(state: DashboardState["workflow"]): string {
  if (state === null) {
    return "status-pill status-pill--muted";
  }
  if (state.state === "PASS" || state.state === "GO") {
    return "status-pill status-pill--pass";
  }
  if (
    state.state === "FAIL" ||
    state.state === "TIMEOUT" ||
    state.state === "RETRY"
  ) {
    return "status-pill status-pill--error";
  }
  if (state.state === "WAIT_START") {
    return "status-pill status-pill--idle";
  }
  return "status-pill status-pill--busy";
}

function formatCaptureTime(timestamp: number): string {
  return new Date(timestamp).toLocaleTimeString("ko-KR", {
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function isDisconnected(transport: DashboardTransport): boolean {
  return transport.connectionState === "disconnected";
}

export interface DashboardBootstrapOptions {
  readonly protocolBridge?: ProtocolBridge;
}

export function bootstrapDashboard(
  options: DashboardBootstrapOptions = {},
): () => Promise<void> {
  const transportSelect = element<HTMLSelectElement>("transportSelect");
  const demoSelect = element<HTMLSelectElement>("demoSelect");
  const scenarioSelect = element<HTMLSelectElement>("scenarioSelect");
  const connectButton = element<HTMLButtonElement>("connectButton");
  const syncButton = element<HTMLButtonElement>("syncButton");
  const startButton = element<HTMLButtonElement>("startButton");
  const freezeButton = element<HTMLButtonElement>("freezeButton");
  const connectionStatus = element<HTMLElement>("connectionStatus");
  const firmwareStatus = element<HTMLElement>("firmwareStatus");
  const liveNotice = element<HTMLElement>("liveNotice");
  const alertBanner = element<HTMLElement>("alertBanner");
  const alertMessage = element<HTMLElement>("alertMessage");
  const dismissAlertButton =
    element<HTMLButtonElement>("dismissAlertButton");
  const waveformElement = element<HTMLCanvasElement>("waveformCanvas");
  const waveformEmpty = element<HTMLElement>("waveformEmpty");
  const viewportLabel = element<HTMLElement>("viewportLabel");
  const zoomFullButton = element<HTMLButtonElement>("zoomFullButton");
  const zoomTriggerButton = element<HTMLButtonElement>("zoomTriggerButton");
  const captureSummary = element<HTMLElement>("captureSummary");
  const lastUpdated = element<HTMLElement>("lastUpdated");
  const clearLogButton = element<HTMLButtonElement>("clearLogButton");
  const domEvents = new AbortController();
  const listen = (
    target: EventTarget,
    type: string,
    listener: EventListener,
  ): void => {
    target.addEventListener(type, listener, { signal: domEvents.signal });
  };

  const store = new DashboardStore();
  const bridge = options.protocolBridge ?? new PendingProtocolBridge();
  const mockTransport = new MockTransport();
  const serialTransport = new WebSerialTransport();
  const transports: Readonly<Record<TransportKind, DashboardTransport>> = {
    mock: mockTransport,
    serial: serialTransport,
  };
  let activeTransport: DashboardTransport = mockTransport;
  let unsubscribeTransport: (() => void) | null = null;
  let renderedCapture: ValidatedCapture | null = null;
  let disposed = false;
  let actionGeneration = 0;
  let disposePromise: Promise<void> | null = null;

  const rawLog = new RawLog(
    element<HTMLOListElement>("rawLogList"),
    element<HTMLElement>("rawLogCount"),
  );
  const demoPanel = new DemoPanel(element<HTMLElement>("demoPanel"));
  const validationPanel = new ValidationPanel(
    element<HTMLElement>("validationPanel"),
  );
  const workflowPanel = new WorkflowPanel(
    element<HTMLElement>("workflowContainer"),
    element<HTMLElement>("transactionBadge"),
  );
  const waveform = new WaveformCanvas(waveformElement, {
    onViewportChange: (window) => {
      renderViewportLabel(window);
    },
  });

  function renderViewportLabel(window: ViewWindow): void {
    const prefix = waveform.viewMode === "full" ? "전체" : "Trigger";
    viewportLabel.textContent =
      `${prefix} · ${window.start}—${window.endExclusive - 1}`;
  }

  function acceptTransportEvent(event: DashboardEvent): void {
    rawLog.accept(event);

    if (event.type === "bytes") {
      for (const semanticEvent of bridge.ingest(event.data)) {
        acceptTransportEvent(semanticEvent);
      }
      return;
    }

    if (
      event.type === "transport" &&
      (event.status.state === "disconnected" ||
        event.status.state === "error")
    ) {
      for (const resetEvent of bridge.reset("disconnect")) {
        acceptTransportEvent(resetEvent);
      }
    }
    store.accept(event);
  }

  function attachTransport(transport: DashboardTransport): void {
    unsubscribeTransport?.();
    activeTransport = transport;
    unsubscribeTransport = transport.subscribe(acceptTransportEvent);
  }

  function render(state: DashboardState): void {
    if (disposed) {
      return;
    }

    connectionStatus.className = connectionTone(state.transport.state);
    connectionStatus.textContent = state.transport.message;
    firmwareStatus.className = firmwareTone(state.workflow);
    firmwareStatus.textContent = state.workflow?.state ?? "UNKNOWN";

    const policy = getControlPolicy(state.transport.state, state.workflow);
    transportSelect.disabled =
      state.transport.state === "connecting" ||
      state.transport.state === "disconnecting";
    connectButton.disabled = !policy.canConnect && !policy.canDisconnect;
    connectButton.classList.toggle("is-connected", policy.canDisconnect);
    connectButton.innerHTML = policy.canDisconnect
      ? '<span class="button-dot" aria-hidden="true"></span>연결 해제'
      : '<span class="button-dot" aria-hidden="true"></span>연결';
    syncButton.disabled = !policy.canSync;
    startButton.disabled = !policy.canStart;
    freezeButton.disabled = !policy.canFinishFreeze;

    const mockConfigurationEnabled =
      activeTransport.kind === "mock" && policy.canConfigureMock;
    demoSelect.disabled = !mockConfigurationEnabled;
    scenarioSelect.disabled = !mockConfigurationEnabled;

    workflowPanel.render(
      state.workflow,
      state.lastGoodCapture,
      state.showingPreviousCapture,
    );

    if (renderedCapture !== state.lastGoodCapture) {
      renderedCapture = state.lastGoodCapture;
      waveform.setCapture(renderedCapture);
      demoPanel.render(renderedCapture);
      validationPanel.render(renderedCapture);
    }

    waveformEmpty.hidden = state.lastGoodCapture !== null;
    alertBanner.hidden = state.alert === null;
    alertMessage.textContent = state.alert ?? "";

    if (state.lastGoodCapture === null) {
      captureSummary.textContent =
        "검증된 Capture가 도착하면 이전 정상 파형을 안전하게 교체합니다.";
      lastUpdated.textContent = "마지막 Capture —";
    } else {
      const capture = state.lastGoodCapture;
      const spec = DEMO_SPECS[capture.metadata.demo];
      captureSummary.textContent = state.showingPreviousCapture
        ? `오류/진행 중 · 이전 검증 TXN ${capture.metadata.transactionId} 유지`
        : `${spec.subtitle} · TXN ${capture.metadata.transactionId} · 1,024 Sample PASS`;
      lastUpdated.textContent =
        `마지막 Capture ${formatCaptureTime(capture.receivedAt)}`;
    }
  }

  async function switchTransport(kind: TransportKind): Promise<void> {
    const generation = actionGeneration + 1;
    actionGeneration = generation;
    const previousTransport = activeTransport;

    if (!isDisconnected(previousTransport)) {
      await previousTransport.disconnect();
      if (disposed || generation !== actionGeneration) {
        return;
      }
      if (!isDisconnected(previousTransport)) {
        transportSelect.value = previousTransport.kind;
        throw new Error("기존 Transport를 완전히 닫지 못했습니다.");
      }
    }

    if (disposed || generation !== actionGeneration) {
      return;
    }

    store.resetSession();
    attachTransport(transports[kind]);
    const serialSelected = kind === "serial";
    liveNotice.hidden = !serialSelected;
    for (const control of document.querySelectorAll<HTMLElement>(".mock-only")) {
      control.hidden = serialSelected;
    }
    render(store.state);
  }

  async function runAction(action: () => Promise<void>): Promise<void> {
    try {
      await action();
    } catch {
      // Transport emitted a user-facing event; avoid a duplicate alert.
    }
  }

  listen(transportSelect, "change", () => {
    void runAction(async () => {
      await switchTransport(transportSelect.value as TransportKind);
    });
  });

  listen(demoSelect, "change", () => {
    (mockTransport as ConfigurableMockTransport).setDemo(
      demoSelect.value as DemoKey,
    );
  });

  listen(scenarioSelect, "change", () => {
    (mockTransport as ConfigurableMockTransport).setScenario(
      scenarioSelect.value as MockScenario,
    );
  });

  listen(connectButton, "click", () => {
    void runAction(async () => {
      if (
        activeTransport.connectionState === "connected" ||
        activeTransport.connectionState === "error"
      ) {
        await activeTransport.disconnect();
        return;
      }
      store.invalidateWorkflow();
      for (const resetEvent of bridge.reset("new-session")) {
        acceptTransportEvent(resetEvent);
      }
      await activeTransport.connect();
    });
  });

  listen(syncButton, "click", () => {
    void runAction(async () => {
      store.invalidateWorkflow();
      for (const resetEvent of bridge.reset("manual-resync")) {
        acceptTransportEvent(resetEvent);
      }
      await activeTransport.sendCommand("?");
    });
  });

  listen(startButton, "click", () => {
    void runAction(() => activeTransport.sendCommand("s"));
  });

  listen(freezeButton, "click", () => {
    void runAction(() => activeTransport.sendCommand("f"));
  });

  listen(zoomFullButton, "click", () => {
    waveform.setViewMode("full");
    zoomFullButton.classList.add("is-active");
    zoomFullButton.setAttribute("aria-pressed", "true");
    zoomTriggerButton.classList.remove("is-active");
    zoomTriggerButton.setAttribute("aria-pressed", "false");
  });

  listen(zoomTriggerButton, "click", () => {
    waveform.setViewMode("trigger");
    zoomTriggerButton.classList.add("is-active");
    zoomTriggerButton.setAttribute("aria-pressed", "true");
    zoomFullButton.classList.remove("is-active");
    zoomFullButton.setAttribute("aria-pressed", "false");
  });

  listen(dismissAlertButton, "click", () => {
    store.clearAlert();
  });
  listen(clearLogButton, "click", () => {
    rawLog.clear();
  });

  const unsubscribeStore = store.subscribe(render);
  attachTransport(mockTransport);
  (mockTransport as ConfigurableMockTransport).setDemo(
    demoSelect.value as DemoKey,
  );
  (mockTransport as ConfigurableMockTransport).setScenario(
    scenarioSelect.value as MockScenario,
  );
  renderViewportLabel(waveform.viewWindow);

  return () => {
    if (disposePromise !== null) {
      return disposePromise;
    }

    disposed = true;
    actionGeneration += 1;
    domEvents.abort();
    unsubscribeStore();
    unsubscribeTransport?.();
    unsubscribeTransport = null;
    waveform.destroy();
    bridge.reset("disconnect");
    const transportToDisconnect = activeTransport;
    disposePromise = isDisconnected(transportToDisconnect)
      ? Promise.resolve()
      : transportToDisconnect.disconnect();
    return disposePromise;
  };
}
