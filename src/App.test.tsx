import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import App from "./App";

describe("App authentication", () => {
  it("blocks an unauthenticated visitor from the root route", async () => {
    render(<App />);
    expect(
      (await screen.findAllByText("Sign in"))[0],
    ).toBeInTheDocument();
  });

  it("offers password recovery without exposing protected navigation", async () => {
    render(<App />);
    expect(await screen.findByText("Forgot password?")).toBeInTheDocument();
    expect(screen.queryByText("New Jewellery Loan")).not.toBeInTheDocument();
  });
});
