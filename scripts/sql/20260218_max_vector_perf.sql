-- Max vector retrieval performance migration (safe/idempotent).
-- This script is resilient to missing tables and will not hard-fail on absent knowledge tables.

create extension if not exists vector;
create extension if not exists pg_trgm;

-- ------------------------------------------------------------------
-- Function signature reset (fix 42P13 on return type changes)
-- ------------------------------------------------------------------
drop function if exists public.match_ai_memories(vector, double precision, integer, text);
drop function if exists public.match_metabolic_knowledge(vector, double precision, integer, text);
drop function if exists public.match_metabolic_knowledge_multi_category(vector, double precision, integer, text[]);

-- ------------------------------------------------------------------
-- ai_memory indexes
-- ------------------------------------------------------------------
do $$
begin
    if to_regclass('public.ai_memory') is null then
        raise notice 'table public.ai_memory not found, skip ai_memory indexes';
    else
        execute 'create index if not exists ai_memory_user_created_idx
                 on public.ai_memory (user_id, created_at desc)';
        execute 'create index if not exists ai_memory_user_role_created_idx
                 on public.ai_memory (user_id, role, created_at desc)';

        if exists (
            select 1
            from information_schema.columns
            where table_schema = 'public'
              and table_name = 'ai_memory'
              and column_name = 'content_text'
        ) then
            execute 'create index if not exists ai_memory_content_trgm_idx
                     on public.ai_memory using gin (content_text gin_trgm_ops)';
        else
            raise notice 'column public.ai_memory.content_text not found, skip trigram index';
        end if;

        if exists (
            select 1
            from information_schema.columns
            where table_schema = 'public'
              and table_name = 'ai_memory'
              and column_name = 'embedding'
        ) then
            if exists (select 1 from pg_am where amname = 'hnsw') then
                execute 'create index if not exists ai_memory_embedding_hnsw_idx
                         on public.ai_memory using hnsw (embedding vector_cosine_ops)';
            else
                execute 'create index if not exists ai_memory_embedding_ivfflat_idx
                         on public.ai_memory using ivfflat (embedding vector_cosine_ops) with (lists = 100)';
            end if;
        else
            raise notice 'column public.ai_memory.embedding not found, skip vector index';
        end if;
    end if;
end $$;

-- ------------------------------------------------------------------
-- metabolic_knowledge indexes
-- ------------------------------------------------------------------
do $$
begin
    if to_regclass('public.metabolic_knowledge') is null then
        raise notice 'table public.metabolic_knowledge not found, skip knowledge indexes';
    else
        execute 'create index if not exists metabolic_knowledge_category_priority_idx
                 on public.metabolic_knowledge (category, priority desc)';
        execute 'create index if not exists metabolic_knowledge_subcategory_idx
                 on public.metabolic_knowledge (subcategory)';

        if exists (
            select 1
            from information_schema.columns
            where table_schema = 'public'
              and table_name = 'metabolic_knowledge'
              and column_name = 'content'
        ) then
            execute 'create index if not exists metabolic_knowledge_content_trgm_idx
                     on public.metabolic_knowledge using gin (content gin_trgm_ops)';
        else
            raise notice 'column public.metabolic_knowledge.content not found, skip trigram index';
        end if;

        if exists (
            select 1
            from information_schema.columns
            where table_schema = 'public'
              and table_name = 'metabolic_knowledge'
              and column_name = 'embedding'
        ) then
            if exists (select 1 from pg_am where amname = 'hnsw') then
                execute 'create index if not exists metabolic_knowledge_embedding_hnsw_idx
                         on public.metabolic_knowledge using hnsw (embedding vector_cosine_ops)';
            else
                execute 'create index if not exists metabolic_knowledge_embedding_ivfflat_idx
                         on public.metabolic_knowledge using ivfflat (embedding vector_cosine_ops) with (lists = 200)';
            end if;
        else
            raise notice 'column public.metabolic_knowledge.embedding not found, skip vector index';
        end if;
    end if;
end $$;

-- ------------------------------------------------------------------
-- RPC: match_ai_memories
-- Safe behavior: returns empty set if table is absent.
-- ------------------------------------------------------------------
create or replace function public.match_ai_memories(
    query_embedding vector,
    match_threshold double precision,
    match_count integer,
    p_user_id text
)
returns table (
    content_text text,
    role text,
    created_at timestamptz,
    similarity double precision
)
language plpgsql
stable
set search_path = public
as $$
begin
    if to_regclass('public.ai_memory') is null then
        return;
    end if;

    return query
    execute $sql$
        with ranked as (
            select
                m.content_text,
                m.role,
                m.created_at,
                1 - (m.embedding <=> $1) as similarity
            from public.ai_memory m
            where m.user_id = $2
              and m.embedding is not null
              and (1 - (m.embedding <=> $1)) >= $3
            order by (m.embedding <=> $1), m.created_at desc
            limit greatest($4 * 4, 24)
        )
        select
            ranked.content_text,
            ranked.role,
            ranked.created_at,
            ranked.similarity
        from ranked
        order by ranked.similarity desc, ranked.created_at desc
        limit greatest($4, 1)
    $sql$
    using query_embedding, p_user_id, match_threshold, match_count;
end;
$$;

comment on function public.match_ai_memories(vector, double precision, integer, text)
is 'Optimized semantic memory retrieval with user filter and similarity gate. Returns empty set if ai_memory is absent.';

-- ------------------------------------------------------------------
-- RPC: match_metabolic_knowledge
-- Safe behavior: returns empty set if table is absent.
-- ------------------------------------------------------------------
create or replace function public.match_metabolic_knowledge(
    query_embedding vector,
    match_threshold double precision,
    match_count integer,
    filter_category text default null
)
returns table (
    content text,
    content_en text,
    category text,
    subcategory text,
    tags jsonb,
    similarity double precision,
    priority integer
)
language plpgsql
stable
set search_path = public
as $$
begin
    if to_regclass('public.metabolic_knowledge') is null then
        return;
    end if;

    return query
    execute $sql$
        with ranked as (
            select
                k.content,
                k.content_en,
                k.category,
                k.subcategory,
                coalesce(to_jsonb(k.tags), '[]'::jsonb) as tags,
                1 - (k.embedding <=> $1) as similarity,
                coalesce(k.priority, 1) as priority
            from public.metabolic_knowledge k
            where k.embedding is not null
              and (1 - (k.embedding <=> $1)) >= $2
              and ($3 is null or k.category = $3)
            order by (k.embedding <=> $1), coalesce(k.priority, 1) desc
            limit greatest($4 * 4, 40)
        )
        select
            ranked.content,
            ranked.content_en,
            ranked.category,
            ranked.subcategory,
            ranked.tags,
            ranked.similarity,
            ranked.priority
        from ranked
        order by ranked.similarity desc, ranked.priority desc
        limit greatest($4, 1)
    $sql$
    using query_embedding, match_threshold, filter_category, match_count;
end;
$$;

comment on function public.match_metabolic_knowledge(vector, double precision, integer, text)
is 'Optimized knowledge retrieval with category filter and priority tie-break. Returns empty set if metabolic_knowledge is absent.';

-- ------------------------------------------------------------------
-- RPC: match_metabolic_knowledge_multi_category
-- Safe behavior: returns empty set if table is absent.
-- ------------------------------------------------------------------
create or replace function public.match_metabolic_knowledge_multi_category(
    query_embedding vector,
    match_threshold double precision,
    match_count integer,
    filter_categories text[] default null
)
returns table (
    content text,
    content_en text,
    category text,
    subcategory text,
    tags jsonb,
    similarity double precision,
    priority integer
)
language plpgsql
stable
set search_path = public
as $$
begin
    if to_regclass('public.metabolic_knowledge') is null then
        return;
    end if;

    return query
    execute $sql$
        with ranked as (
            select
                k.content,
                k.content_en,
                k.category,
                k.subcategory,
                coalesce(to_jsonb(k.tags), '[]'::jsonb) as tags,
                1 - (k.embedding <=> $1) as similarity,
                coalesce(k.priority, 1) as priority
            from public.metabolic_knowledge k
            where k.embedding is not null
              and (1 - (k.embedding <=> $1)) >= $2
              and (
                  $3 is null
                  or array_length($3, 1) is null
                  or k.category = any($3)
              )
            order by (k.embedding <=> $1), coalesce(k.priority, 1) desc
            limit greatest($4 * 4, 40)
        )
        select
            ranked.content,
            ranked.content_en,
            ranked.category,
            ranked.subcategory,
            ranked.tags,
            ranked.similarity,
            ranked.priority
        from ranked
        order by ranked.similarity desc, ranked.priority desc
        limit greatest($4, 1)
    $sql$
    using query_embedding, match_threshold, filter_categories, match_count;
end;
$$;

comment on function public.match_metabolic_knowledge_multi_category(vector, double precision, integer, text[])
is 'Optimized knowledge retrieval with multi-category filter and priority tie-break. Returns empty set if metabolic_knowledge is absent.';

-- ------------------------------------------------------------------
-- ANALYZE (safe)
-- ------------------------------------------------------------------
do $$
begin
    if to_regclass('public.ai_memory') is not null then
        analyze public.ai_memory;
    else
        raise notice 'table public.ai_memory not found, skip analyze';
    end if;

    if to_regclass('public.metabolic_knowledge') is not null then
        analyze public.metabolic_knowledge;
    else
        raise notice 'table public.metabolic_knowledge not found, skip analyze';
    end if;
end $$;
