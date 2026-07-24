--
-- PostgreSQL database dump
--

\restrict zc8cyQd9bbkXMQhgssIvqXwpIXbilSAjQ3BpHCV26MMnseeZcBmUZyqDGOmFQ5k

-- Dumped from database version 18.4 (Debian 18.4-1.pgdg12+1)
-- Dumped by pg_dump version 18.4 (Debian 18.4-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: global_registry; Type: SCHEMA; Schema: -; Owner: postgres_admin
--

CREATE SCHEMA global_registry;


ALTER SCHEMA global_registry OWNER TO postgres_admin;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: postgres_admin
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'suspended',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


ALTER TYPE public.oban_job_state OWNER TO postgres_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_tokens; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.account_tokens (
    id bigint NOT NULL,
    account_id bigint NOT NULL,
    token bytea NOT NULL,
    context character varying(255) NOT NULL,
    sent_to character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL
);


ALTER TABLE global_registry.account_tokens OWNER TO postgres_admin;

--
-- Name: account_tokens_id_seq; Type: SEQUENCE; Schema: global_registry; Owner: postgres_admin
--

CREATE SEQUENCE global_registry.account_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global_registry.account_tokens_id_seq OWNER TO postgres_admin;

--
-- Name: account_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: global_registry; Owner: postgres_admin
--

ALTER SEQUENCE global_registry.account_tokens_id_seq OWNED BY global_registry.account_tokens.id;


--
-- Name: accounts; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.accounts (
    id bigint NOT NULL,
    email public.citext NOT NULL,
    name character varying(255),
    hashed_password character varying(255),
    role character varying(255) DEFAULT 'user'::character varying NOT NULL,
    tenant_id character varying(255),
    confirmed_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    suspended_at timestamp(0) without time zone
);


ALTER TABLE global_registry.accounts OWNER TO postgres_admin;

--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: global_registry; Owner: postgres_admin
--

CREATE SEQUENCE global_registry.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global_registry.accounts_id_seq OWNER TO postgres_admin;

--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: global_registry; Owner: postgres_admin
--

ALTER SEQUENCE global_registry.accounts_id_seq OWNED BY global_registry.accounts.id;


--
-- Name: gdpr_audit_log; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.gdpr_audit_log (
    id bigint NOT NULL,
    action text NOT NULL,
    subject_id text NOT NULL,
    performed_by text NOT NULL,
    details jsonb,
    performed_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE global_registry.gdpr_audit_log OWNER TO postgres_admin;

--
-- Name: gdpr_audit_log_id_seq; Type: SEQUENCE; Schema: global_registry; Owner: postgres_admin
--

CREATE SEQUENCE global_registry.gdpr_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global_registry.gdpr_audit_log_id_seq OWNER TO postgres_admin;

--
-- Name: gdpr_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: global_registry; Owner: postgres_admin
--

ALTER SEQUENCE global_registry.gdpr_audit_log_id_seq OWNED BY global_registry.gdpr_audit_log.id;


--
-- Name: incoming_emails; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.incoming_emails (
    id bigint NOT NULL,
    from_address character varying(255) NOT NULL,
    subject character varying(255),
    body_text text,
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    received_at timestamp(0) without time zone NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL,
    attachments jsonb[] DEFAULT ARRAY[]::jsonb[]
);


ALTER TABLE global_registry.incoming_emails OWNER TO postgres_admin;

--
-- Name: incoming_emails_id_seq; Type: SEQUENCE; Schema: global_registry; Owner: postgres_admin
--

CREATE SEQUENCE global_registry.incoming_emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global_registry.incoming_emails_id_seq OWNER TO postgres_admin;

--
-- Name: incoming_emails_id_seq; Type: SEQUENCE OWNED BY; Schema: global_registry; Owner: postgres_admin
--

ALTER SEQUENCE global_registry.incoming_emails_id_seq OWNED BY global_registry.incoming_emails.id;


--
-- Name: module_registry; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.module_registry (
    id bigint NOT NULL,
    workflow_name character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    workflow_id character varying(255),
    params_schema jsonb,
    prompt_hint character varying(255),
    active boolean DEFAULT true
);


ALTER TABLE global_registry.module_registry OWNER TO postgres_admin;

--
-- Name: module_registry_id_seq; Type: SEQUENCE; Schema: global_registry; Owner: postgres_admin
--

CREATE SEQUENCE global_registry.module_registry_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global_registry.module_registry_id_seq OWNER TO postgres_admin;

--
-- Name: module_registry_id_seq; Type: SEQUENCE OWNED BY; Schema: global_registry; Owner: postgres_admin
--

ALTER SEQUENCE global_registry.module_registry_id_seq OWNED BY global_registry.module_registry.id;


--
-- Name: tenant_workflow_overrides; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.tenant_workflow_overrides (
    tenant_id text NOT NULL,
    workflow_name text NOT NULL,
    enabled boolean DEFAULT true NOT NULL
);


ALTER TABLE global_registry.tenant_workflow_overrides OWNER TO postgres_admin;

--
-- Name: tenants; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.tenants (
    id bigint NOT NULL,
    tenant_id character varying(255) NOT NULL,
    company_name character varying(255) NOT NULL,
    schema_name character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    admin_email character varying(255),
    webhook_url text,
    webhook_secret text,
    inserted_at timestamp(0) without time zone NOT NULL
);


ALTER TABLE global_registry.tenants OWNER TO postgres_admin;

--
-- Name: tenants_id_seq; Type: SEQUENCE; Schema: global_registry; Owner: postgres_admin
--

CREATE SEQUENCE global_registry.tenants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global_registry.tenants_id_seq OWNER TO postgres_admin;

--
-- Name: tenants_id_seq; Type: SEQUENCE OWNED BY; Schema: global_registry; Owner: postgres_admin
--

ALTER SEQUENCE global_registry.tenants_id_seq OWNED BY global_registry.tenants.id;


--
-- Name: user_mappings; Type: TABLE; Schema: global_registry; Owner: postgres_admin
--

CREATE TABLE global_registry.user_mappings (
    id bigint NOT NULL,
    tenant_id character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    telegram_id character varying(255),
    status text DEFAULT 'active'::text NOT NULL
);


ALTER TABLE global_registry.user_mappings OWNER TO postgres_admin;

--
-- Name: user_mappings_id_seq; Type: SEQUENCE; Schema: global_registry; Owner: postgres_admin
--

CREATE SEQUENCE global_registry.user_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global_registry.user_mappings_id_seq OWNER TO postgres_admin;

--
-- Name: user_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: global_registry; Owner: postgres_admin
--

ALTER SEQUENCE global_registry.user_mappings_id_seq OWNED BY global_registry.user_mappings.id;


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: postgres_admin
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags text[] DEFAULT ARRAY[]::text[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


ALTER TABLE public.oban_jobs OWNER TO postgres_admin;

--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: postgres_admin
--

COMMENT ON TABLE public.oban_jobs IS '14';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres_admin
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.oban_jobs_id_seq OWNER TO postgres_admin;

--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres_admin
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: postgres_admin
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


ALTER TABLE public.oban_peers OWNER TO postgres_admin;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: postgres_admin
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


ALTER TABLE public.schema_migrations OWNER TO postgres_admin;

--
-- Name: account_tokens id; Type: DEFAULT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.account_tokens ALTER COLUMN id SET DEFAULT nextval('global_registry.account_tokens_id_seq'::regclass);


--
-- Name: accounts id; Type: DEFAULT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.accounts ALTER COLUMN id SET DEFAULT nextval('global_registry.accounts_id_seq'::regclass);


--
-- Name: gdpr_audit_log id; Type: DEFAULT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.gdpr_audit_log ALTER COLUMN id SET DEFAULT nextval('global_registry.gdpr_audit_log_id_seq'::regclass);


--
-- Name: incoming_emails id; Type: DEFAULT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.incoming_emails ALTER COLUMN id SET DEFAULT nextval('global_registry.incoming_emails_id_seq'::regclass);


--
-- Name: module_registry id; Type: DEFAULT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.module_registry ALTER COLUMN id SET DEFAULT nextval('global_registry.module_registry_id_seq'::regclass);


--
-- Name: tenants id; Type: DEFAULT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.tenants ALTER COLUMN id SET DEFAULT nextval('global_registry.tenants_id_seq'::regclass);


--
-- Name: user_mappings id; Type: DEFAULT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.user_mappings ALTER COLUMN id SET DEFAULT nextval('global_registry.user_mappings_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: postgres_admin
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: account_tokens account_tokens_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.account_tokens
    ADD CONSTRAINT account_tokens_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: gdpr_audit_log gdpr_audit_log_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.gdpr_audit_log
    ADD CONSTRAINT gdpr_audit_log_pkey PRIMARY KEY (id);


--
-- Name: incoming_emails incoming_emails_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.incoming_emails
    ADD CONSTRAINT incoming_emails_pkey PRIMARY KEY (id);


--
-- Name: module_registry module_registry_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.module_registry
    ADD CONSTRAINT module_registry_pkey PRIMARY KEY (id);


--
-- Name: tenant_workflow_overrides tenant_workflow_overrides_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.tenant_workflow_overrides
    ADD CONSTRAINT tenant_workflow_overrides_pkey PRIMARY KEY (tenant_id, workflow_name);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: user_mappings user_mappings_pkey; Type: CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.user_mappings
    ADD CONSTRAINT user_mappings_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs non_negative_priority; Type: CHECK CONSTRAINT; Schema: public; Owner: postgres_admin
--

ALTER TABLE public.oban_jobs
    ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres_admin
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres_admin
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres_admin
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: account_tokens_account_id_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE INDEX account_tokens_account_id_index ON global_registry.account_tokens USING btree (account_id);


--
-- Name: account_tokens_context_token_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE UNIQUE INDEX account_tokens_context_token_index ON global_registry.account_tokens USING btree (context, token);


--
-- Name: accounts_email_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE UNIQUE INDEX accounts_email_index ON global_registry.accounts USING btree (email);


--
-- Name: idx_gdpr_audit_log_performed_at; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE INDEX idx_gdpr_audit_log_performed_at ON global_registry.gdpr_audit_log USING btree (performed_at);


--
-- Name: idx_gdpr_audit_log_subject; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE INDEX idx_gdpr_audit_log_subject ON global_registry.gdpr_audit_log USING btree (subject_id);


--
-- Name: incoming_emails_received_at_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE INDEX incoming_emails_received_at_index ON global_registry.incoming_emails USING btree (received_at);


--
-- Name: incoming_emails_status_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE INDEX incoming_emails_status_index ON global_registry.incoming_emails USING btree (status);


--
-- Name: module_registry_workflow_name_action_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE UNIQUE INDEX module_registry_workflow_name_action_index ON global_registry.module_registry USING btree (workflow_name, action);


--
-- Name: tenants_tenant_id_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE UNIQUE INDEX tenants_tenant_id_index ON global_registry.tenants USING btree (tenant_id);


--
-- Name: user_mappings_email_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE UNIQUE INDEX user_mappings_email_index ON global_registry.user_mappings USING btree (email);


--
-- Name: user_mappings_telegram_id_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE UNIQUE INDEX user_mappings_telegram_id_index ON global_registry.user_mappings USING btree (telegram_id) WHERE (telegram_id IS NOT NULL);


--
-- Name: user_mappings_tenant_id_index; Type: INDEX; Schema: global_registry; Owner: postgres_admin
--

CREATE INDEX user_mappings_tenant_id_index ON global_registry.user_mappings USING btree (tenant_id);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: postgres_admin
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: postgres_admin
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_cancelled_at_index; Type: INDEX; Schema: public; Owner: postgres_admin
--

CREATE INDEX oban_jobs_state_cancelled_at_index ON public.oban_jobs USING btree (state, cancelled_at);


--
-- Name: oban_jobs_state_discarded_at_index; Type: INDEX; Schema: public; Owner: postgres_admin
--

CREATE INDEX oban_jobs_state_discarded_at_index ON public.oban_jobs USING btree (state, discarded_at);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: postgres_admin
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: account_tokens account_tokens_account_id_fkey; Type: FK CONSTRAINT; Schema: global_registry; Owner: postgres_admin
--

ALTER TABLE ONLY global_registry.account_tokens
    ADD CONSTRAINT account_tokens_account_id_fkey FOREIGN KEY (account_id) REFERENCES global_registry.accounts(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict zc8cyQd9bbkXMQhgssIvqXwpIXbilSAjQ3BpHCV26MMnseeZcBmUZyqDGOmFQ5k

