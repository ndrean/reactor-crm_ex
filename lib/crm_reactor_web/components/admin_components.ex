defmodule CrmReactorWeb.AdminComponents do
  @moduledoc "Shared function components for admin LiveViews."
  use Phoenix.Component

  attr :rows, :list, required: true
  attr :cols, :list, required: true
  attr :id, :string, default: "admin-table"
  slot :col, required: true

  def admin_table(assigns) do
    ~H"""
    <div style="overflow-x:auto;max-height:70vh;overflow-y:auto;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);">
      <table style="width:100%;border-collapse:collapse;background:#fff;">
        <thead style="position:sticky;top:0;background:#fff;z-index:1;">
          <tr>
            <th :for={col <- @cols} style="text-align:left;padding:10px 16px;font-size:0.8rem;font-weight:500;color:#666;border-bottom:1px solid #eee;text-transform:uppercase;letter-spacing:0.04em;">
              <%= col %>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update="stream">
          <tr :for={{dom_id, _item} = row <- @rows} id={dom_id} style="border-bottom:1px solid #f0f0f0;">
            <%= render_slot(@col, row) %>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :phx_submit, :string, required: true
  attr :phx_change, :string, default: "noop"
  slot :inner_block, required: true

  def admin_form(assigns) do
    ~H"""
    <form id={@id} phx-submit={@phx_submit} phx-change={@phx_change} style="background:#fff;padding:20px 24px;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,0.06);margin-bottom:24px;display:flex;gap:12px;align-items:end;flex-wrap:wrap;">
      <%= render_slot(@inner_block) %>
    </form>
    """
  end

  def flash_group(assigns) do
    ~H"""
    <p :if={Phoenix.Flash.get(@flash, :info)} class="flash-info" phx-click="lv:clear-flash" phx-value-key="info">
      <%= Phoenix.Flash.get(@flash, :info) %>
    </p>
    <p :if={Phoenix.Flash.get(@flash, :error)} class="flash-error" phx-click="lv:clear-flash" phx-value-key="error">
      <%= Phoenix.Flash.get(@flash, :error) %>
    </p>
    """
  end
end
