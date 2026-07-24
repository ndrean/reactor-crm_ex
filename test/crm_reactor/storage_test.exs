defmodule CrmReactor.StorageTest do
  use ExUnit.Case, async: false

  alias CrmReactor.Storage
  alias CrmReactor.Storage.Local

  @schema "tenant_test"
  @filename "hello.txt"
  @content "hello world"

  setup do
    tmp = System.tmp_dir!() |> Path.join("crm_storage_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev_path = Application.get_env(:crm_reactor, :storage_path)
    prev_backend = Application.get_env(:crm_reactor, :file_storage)
    Application.put_env(:crm_reactor, :storage_path, tmp)
    Application.put_env(:crm_reactor, :file_storage, CrmReactor.Storage.Local)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:crm_reactor, :storage_path, prev_path)
      Application.put_env(:crm_reactor, :file_storage, prev_backend)
    end)

    :ok
  end

  # ── Storage (behaviour dispatcher) ──────────────────────────────────

  test "put/3 stores file and returns {:ok, key}" do
    assert {:ok, key} = Storage.put(@schema, @filename, @content)
    assert String.starts_with?(key, @schema)
    assert String.ends_with?(key, "hello.txt")
  end

  test "put/3 rejects content over 5 MB" do
    large = :binary.copy("x", 5 * 1024 * 1024 + 1)
    assert {:error, :file_too_large} = Storage.put(@schema, @filename, large)
  end

  test "get/1 returns file content after put" do
    {:ok, key} = Storage.put(@schema, @filename, @content)
    assert {:ok, @content} = Storage.get(key)
  end

  test "get/1 returns error for missing key" do
    assert {:error, _} = Storage.get("nonexistent/missing.txt")
  end

  test "delete/1 removes file, subsequent get fails" do
    {:ok, key} = Storage.put(@schema, @filename, @content)
    assert :ok = Storage.delete(key)
    assert {:error, _} = Storage.get(key)
  end

  test "delete/1 on nonexistent key returns :ok" do
    assert :ok = Storage.delete("ghost/file.txt")
  end

  # ── Storage.Local ─────────────────────────────────────────────────

  test "Local.put sanitizes filename" do
    {:ok, key} = Local.put(@schema, "my file (1).txt", @content)
    refute String.contains?(key, " ")
    refute String.contains?(key, "(")
  end

  test "Local.put truncates filename to 60 chars" do
    long = String.duplicate("a", 80) <> ".txt"
    {:ok, key} = Local.put(@schema, long, @content)
    filename_part = key |> String.split("/") |> List.last()
    # uuid-sanitized_filename; the sanitized part should be at most 60 chars
    sanitized = filename_part |> String.split("-", parts: 6) |> List.last()
    assert String.length(sanitized) <= 60
  end

  test "Local.get returns :enoent for missing file" do
    assert {:error, :enoent} = Local.get("no/such/file.txt")
  end

  test "Local.delete is idempotent for nonexistent file" do
    assert :ok = Local.delete("no/such/file.txt")
  end
end
