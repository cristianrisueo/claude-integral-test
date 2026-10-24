import { useEffect, useState } from "react";
import { checkHealth, type HealthState } from "./health";

const labels = {
  ok: { api: "ok", database: "ok" },
  "database-unreachable": { api: "ok", database: "unreachable" },
  "api-unreachable": { api: "unreachable", database: "unknown" },
};

export default function App() {
  const [state, setState] = useState<HealthState>("checking");

  useEffect(() => {
    let active = true;
    checkHealth().then((result) => {
      if (active) setState(result);
    });
    return () => {
      active = false;
    };
  }, []);

  if (state === "checking") {
    return (
      <main>
        <p>Checking…</p>
      </main>
    );
  }

  const { api, database } = labels[state];
  return (
    <main>
      <p>{`API: ${api}`}</p>
      <p>{`Database: ${database}`}</p>
    </main>
  );
}
