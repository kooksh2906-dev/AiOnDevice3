import "./styles.css";

import { PendingProtocolBridge } from "./app/protocolBridge";
import { bootstrapDashboard } from "./main";

const dispose = bootstrapDashboard({
  protocolBridge: new PendingProtocolBridge(),
});

if (import.meta.hot !== undefined) {
  import.meta.hot.dispose(() => {
    void dispose();
  });
}
