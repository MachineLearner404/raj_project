import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { SearchBar } from "./SearchBar";

describe("SearchBar", () => {
  it("calls onChange as the user types", async () => {
    const onChange = vi.fn();
    render(<SearchBar value="" onChange={onChange} placeholder="Search…" />);
    await userEvent.type(screen.getByPlaceholderText("Search…"), "a");
    expect(onChange).toHaveBeenCalledWith("a");
  });

  it("shows a clear button only when there is a value, and clears on click", async () => {
    const onChange = vi.fn();
    const { rerender } = render(
      <SearchBar value="" onChange={onChange} placeholder="Search…" />,
    );
    expect(screen.queryByLabelText("Clear search")).not.toBeInTheDocument();

    rerender(<SearchBar value="ramesh" onChange={onChange} placeholder="Search…" />);
    const clearButton = screen.getByLabelText("Clear search");
    await userEvent.click(clearButton);
    expect(onChange).toHaveBeenCalledWith("");
  });
});
