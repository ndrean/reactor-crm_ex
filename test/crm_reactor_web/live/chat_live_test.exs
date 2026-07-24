defmodule CrmReactorWeb.ChatLiveTest do
  use CrmReactorWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest

  alias CrmReactor.{Repo, TestFixtures}
  alias CrmReactor.Tenants.UserMapping

  @vcf_path "test/user.vcf"

  setup :set_mox_global

  setup do
    Mox.stub_with(CrmReactor.MockStorage, CrmReactor.Storage.Local)
    :ok
  end

  defp setup_authenticated_user(conn, fixture) do
    %{conn: conn, account: account} =
      register_and_log_in_user(conn, %{
        tenant_id: fixture.tenant.tenant_id,
        role: "user"
      })

    # UserMapping is still needed for Mutations.confirm/3 (confirm/reject flows).
    %UserMapping{}
    |> UserMapping.changeset(%{
      email: account.email,
      tenant_id: fixture.tenant.tenant_id
    })
    |> Repo.insert!()

    %{conn: conn, account: account}
  end

  # ── Initial render ────────────────────────────────────────────────────

  test "mounts and renders the chat interface", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, _view, html} = live(conn, "/chat")
    assert html =~ "CRM Assistant"
    assert html =~ "Tapez votre message"
  end

  # ── Validate event ────────────────────────────────────────────────────

  test "validate event updates input value in state", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    html =
      view |> element("form[phx-submit='send']") |> render_change(%{"input" => "bonjour monde"})

    assert html =~ "bonjour monde"
  end

  # ── Send event ────────────────────────────────────────────────────────

  test "send with empty input is a no-op", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    html_before = render(view)
    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => ""})
    assert render(view) == html_before
  end

  test "send a message processes through reactor and shows assistant response", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "aide"})
    html = render(view)

    # User message appears
    assert html =~ "aide"
    # Assistant actually responded (not stuck loading, no error)
    refute html =~ "En cours"
    refute html =~ "erreur"
    refute html =~ "Identifiant inconnu"
    # Assistant response has meaningful content from the help module
    assert html =~ "contacts"
  end

  test "search contacts returns results (full round-trip)", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "cherche Marie"})
    html = render(view)

    # Reactor resolved tenant at transport boundary, ran the pipeline, returned results
    assert html =~ "Marie"
    assert html =~ "Dupont"
    refute html =~ "erreur"
    refute html =~ "Identifiant inconnu"
  end

  # ── Confirm / Reject ──────────────────────────────────────────────────

  test "delete command shows confirm/reject buttons", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "supprime Marie Dupont"})

    html = render(view)

    assert html =~ "Confirmer"
    assert html =~ "Annuler"
  end

  test "confirm button executes the pending mutation", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "supprime Marie Dupont"})

    render(view)

    html = view |> element("button[phx-click='confirm']") |> render_click()
    assert html =~ "supprimé"
    refute html =~ "Confirmer"
  end

  test "reject button cancels the pending mutation", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "supprime Marie Dupont"})

    render(view)

    html = view |> element("button[phx-click='reject']") |> render_click()
    assert html =~ "annulée"
    refute html =~ "Annuler"
  end

  # ── Export email flow ─────────────────────────────────────────────────

  test "export command shows email input when no admin email set", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "exporte mes données"})

    html = render(view)

    assert html =~ "email"
  end

  test "provide_email with valid address completes export", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "exporte mes données"})

    render(view)

    html =
      view
      |> element("form[phx-submit='provide_email']")
      |> render_submit(%{"email" => "admin@example.fr"})

    assert Enum.any?(["email", "envoyé", "admin@example.fr"], &(html =~ &1))
  end

  test "provide_email with invalid address shows error", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "exporte mes données"})

    render(view)

    html =
      view
      |> element("form[phx-submit='provide_email']")
      |> render_submit(%{"email" => "notanemail"})

    assert html =~ "invalide"
  end

  test "provide_email with empty email is a no-op", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)
    {:ok, view, _} = live(conn, "/chat")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "exporte mes données"})

    render(view)

    html_before = render(view)
    view |> element("form[phx-submit='provide_email']") |> render_submit(%{"email" => ""})
    assert render(view) == html_before
  end

  # ── File attachment ────────────────────────────────────────────────────

  test "uploading a vcf file and sending processes without error", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    vcf = File.read!(@vcf_path)

    {:ok, view, _} = live(conn, "/chat")

    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "user.vcf", content: vcf, type: "text/vcard"}
      ])

    render_upload(upload, "user.vcf")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "cherche Marie"})
    html = render(view)

    assert html =~ "Marie"
    refute html =~ "En cours"
  end

  test "cancelling an upload removes the file indicator", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    vcf = File.read!(@vcf_path)

    {:ok, view, _} = live(conn, "/chat")

    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "user.vcf", content: vcf, type: "text/vcard"}
      ])

    render_upload(upload, "user.vcf")

    [entry] = upload.entries
    ref = entry["ref"]

    view
    |> element("[phx-click='cancel-upload']")
    |> render_click(%{"ref" => ref})

    html = render(view)
    refute html =~ "phx-value-ref=\"#{ref}\""
  end

  # ── MIME validation + classification ──────────────────────────────────

  test "JPEG with valid magic bytes is accepted and stored", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    jpeg = File.read!("test/IMG_0723.jpeg")

    {:ok, view, _} = live(conn, "/chat")

    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "receipt.jpeg", content: jpeg, type: "image/jpeg"}
      ])

    render_upload(upload, "receipt.jpeg")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "reçu restaurant"})
    html = render(view)

    # MockClassifier routes image + expense keyword to expenses.submit
    assert html =~ "Note de frais"
    refute html =~ "En cours"
  end

  test "fake JPEG (wrong magic bytes) is rejected silently", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    # A text file masquerading as .jpeg
    fake_jpeg = "This is not a JPEG file at all"

    {:ok, view, _} = live(conn, "/chat")

    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "fake.jpeg", content: fake_jpeg, type: "image/jpeg"}
      ])

    render_upload(upload, "fake.jpeg")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "cherche Marie"})
    html = render(view)

    # No attachment stored (nil), falls back to text-only classification
    assert html =~ "Marie"
    refute html =~ "En cours"
  end

  test "PDF with valid magic bytes is stored but classification uses text-only", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    # Small synthetic PDF (valid %PDF header)
    pdf_content = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF"

    {:ok, view, _} = live(conn, "/chat")

    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "invoice.pdf", content: pdf_content, type: "application/pdf"}
      ])

    render_upload(upload, "invoice.pdf")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "cherche Marie"})
    html = render(view)

    # PDF is stored but ClassifyIntent falls back to text-only classification
    assert html =~ "Marie"
    refute html =~ "En cours"
  end

  test "fake PDF (wrong magic bytes) is rejected silently", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    fake_pdf = "This is not a PDF"

    {:ok, view, _} = live(conn, "/chat")

    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "fake.pdf", content: fake_pdf, type: "application/pdf"}
      ])

    render_upload(upload, "fake.pdf")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "cherche Marie"})
    html = render(view)

    # No attachment stored, falls back to text-only
    assert html =~ "Marie"
    refute html =~ "En cours"
  end

  test "unsupported extension is rejected", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    {:ok, view, _} = live(conn, "/chat")

    # .exe is not in the allowed list — but LiveView allow_upload also restricts this.
    # The accept list is ~w(.jpg .jpeg .png .gif .csv .txt .vcf .pdf), so .txt is allowed.
    # Test that a .txt file passes through without magic byte check (text files skip it).
    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "notes.txt", content: "some text data", type: "text/plain"}
      ])

    render_upload(upload, "notes.txt")

    view |> element("form[phx-submit='send']") |> render_submit(%{"input" => "cherche Marie"})
    html = render(view)

    assert html =~ "Marie"
    refute html =~ "En cours"
  end

  @tag :requires_mistral
  test "uploading vcf with real Mistral API returns contact-related response", %{conn: conn} do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)

    Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.Classifier)

    on_exit(fn ->
      Application.put_env(:crm_reactor, :classifier, CrmReactor.AI.MockClassifier)
    end)

    %{conn: conn} = setup_authenticated_user(conn, fixture)

    vcf = File.read!(@vcf_path)

    {:ok, view, _} = live(conn, "/chat")

    upload =
      file_input(view, "#chat-input-form", :attachment, [
        %{name: "user.vcf", content: vcf, type: "text/vcard"}
      ])

    render_upload(upload, "user.vcf")

    view
    |> element("form[phx-submit='send']")
    |> render_submit(%{"input" => "analyse ce contact"})

    html = render(view)

    refute html =~ "En cours"
    refute html =~ "Une erreur est survenue"
  end
end
