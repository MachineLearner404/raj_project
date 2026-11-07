import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { DataTable, type DataTableColumn } from "./DataTable";

interface Row {
  id: string;
  name: string;
}

const columns: DataTableColumn<Row>[] = [
  { key: "name", header: "Name", render: (r) => r.name },
];

describe("DataTable", () => {
  it("renders a row per item", () => {
    render(
      <DataTable
        columns={columns}
        rows={[{ id: "1", name: "Ramesh" }, { id: "2", name: "Sunita" }]}
        getRowId={(r) => r.id}
      />,
    );
    expect(screen.getByText("Ramesh")).toBeInTheDocument();
    expect(screen.getByText("Sunita")).toBeInTheDocument();
  });

  it("shows the empty state when there are no rows", () => {
    render(<DataTable columns={columns} rows={[]} getRowId={(r) => r.id} />);
    expect(screen.getByText("Nothing to show")).toBeInTheDocument();
  });

  it("shows a loading skeleton instead of rows when isLoading", () => {
    render(
      <DataTable
        columns={columns}
        rows={[{ id: "1", name: "Ramesh" }]}
        getRowId={(r) => r.id}
        isLoading
      />,
    );
    expect(screen.queryByText("Ramesh")).not.toBeInTheDocument();
  });
});
