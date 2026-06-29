import { ImageResponse } from "next/og";

export const alt = "Rubber Duck — Talk through your code with AI";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: "100px",
        backgroundColor: "#1c1c1e",
      }}
    >
      <div
        style={{
          fontSize: 88,
          fontWeight: 700,
          color: "#f5f5f7",
          letterSpacing: "-0.04em",
        }}
      >
        Rubber Duck
      </div>
      <div style={{ fontSize: 44, color: "#c5c5ca", marginTop: 16 }}>
        Talk through your code with AI.
      </div>
      <div style={{ fontSize: 30, color: "#98989d", marginTop: 28 }}>
        A macOS menu bar voice coding agent.
      </div>
    </div>,
    { ...size },
  );
}
