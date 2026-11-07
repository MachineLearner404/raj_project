import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { StatusBadge } from "./StatusBadge";

describe("StatusBadge", () => {
  it.each([
    ["active", "Active"],
    ["overdue", "Overdue"],
    ["completed", "Completed"],
    ["auctioned", "Auctioned"],
  ] as const)("renders the %s status as %s", (status, label) => {
    render(<StatusBadge status={status} />);
    expect(screen.getByText(label)).toBeInTheDocument();
  });
});
