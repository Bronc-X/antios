-- Capture pipeline hardening:
-- 1) Ensure chat/session/memory tables are writable by the owning authenticated user
-- 2) Keep policy creation idempotent
-- 3) Optionally align legacy chat_conversations schema with session_id support

-- ------------------------------------------------------------------
-- chat_sessions: RLS + owner policies
-- ------------------------------------------------------------------
do $$
begin
    if to_regclass('public.chat_sessions') is null then
        raise notice 'table public.chat_sessions not found, skip';
    else
        execute 'alter table public.chat_sessions enable row level security';
        execute 'grant select, insert, update, delete on table public.chat_sessions to authenticated';

        execute 'drop policy if exists chat_sessions_select_own on public.chat_sessions';
        execute 'drop policy if exists chat_sessions_insert_own on public.chat_sessions';
        execute 'drop policy if exists chat_sessions_update_own on public.chat_sessions';
        execute 'drop policy if exists chat_sessions_delete_own on public.chat_sessions';

        execute 'create policy chat_sessions_select_own on public.chat_sessions
                 for select to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy chat_sessions_insert_own on public.chat_sessions
                 for insert to authenticated
                 with check (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy chat_sessions_update_own on public.chat_sessions
                 for update to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)
                 with check (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy chat_sessions_delete_own on public.chat_sessions
                 for delete to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)';
    end if;
end $$;

-- ------------------------------------------------------------------
-- chat_conversations: optional legacy column upgrade + RLS
-- ------------------------------------------------------------------
do $$
declare
    has_session_id boolean;
begin
    if to_regclass('public.chat_conversations') is null then
        raise notice 'table public.chat_conversations not found, skip';
    else
        select exists (
            select 1
            from information_schema.columns
            where table_schema = 'public'
              and table_name = 'chat_conversations'
              and column_name = 'session_id'
        ) into has_session_id;

        if not has_session_id then
            execute 'alter table public.chat_conversations add column session_id uuid';
            raise notice 'added public.chat_conversations.session_id (uuid)';
        end if;

        execute 'create index if not exists chat_conversations_user_created_idx
                 on public.chat_conversations (user_id, created_at desc)';
        execute 'create index if not exists chat_conversations_session_created_idx
                 on public.chat_conversations (session_id, created_at desc)';

        execute 'alter table public.chat_conversations enable row level security';
        execute 'grant select, insert, update, delete on table public.chat_conversations to authenticated';

        execute 'drop policy if exists chat_conversations_select_own on public.chat_conversations';
        execute 'drop policy if exists chat_conversations_insert_own on public.chat_conversations';
        execute 'drop policy if exists chat_conversations_update_own on public.chat_conversations';
        execute 'drop policy if exists chat_conversations_delete_own on public.chat_conversations';

        execute 'create policy chat_conversations_select_own on public.chat_conversations
                 for select to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy chat_conversations_insert_own on public.chat_conversations
                 for insert to authenticated
                 with check (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy chat_conversations_update_own on public.chat_conversations
                 for update to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)
                 with check (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy chat_conversations_delete_own on public.chat_conversations
                 for delete to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)';
    end if;
end $$;

-- ------------------------------------------------------------------
-- ai_memory: RLS + owner policies
-- ------------------------------------------------------------------
do $$
begin
    if to_regclass('public.ai_memory') is null then
        raise notice 'table public.ai_memory not found, skip';
    else
        execute 'alter table public.ai_memory enable row level security';
        execute 'grant select, insert, update, delete on table public.ai_memory to authenticated';

        execute 'drop policy if exists ai_memory_select_own on public.ai_memory';
        execute 'drop policy if exists ai_memory_insert_own on public.ai_memory';
        execute 'drop policy if exists ai_memory_update_own on public.ai_memory';
        execute 'drop policy if exists ai_memory_delete_own on public.ai_memory';

        execute 'create policy ai_memory_select_own on public.ai_memory
                 for select to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy ai_memory_insert_own on public.ai_memory
                 for insert to authenticated
                 with check (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy ai_memory_update_own on public.ai_memory
                 for update to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)
                 with check (auth.uid() is not null and auth.uid()::text = user_id::text)';
        execute 'create policy ai_memory_delete_own on public.ai_memory
                 for delete to authenticated
                 using (auth.uid() is not null and auth.uid()::text = user_id::text)';
    end if;
end $$;

-- ------------------------------------------------------------------
-- RPC grants for authenticated clients
-- ------------------------------------------------------------------
do $$
begin
    if to_regprocedure('public.match_ai_memories(vector,double precision,integer,text)') is not null then
        execute 'grant execute on function public.match_ai_memories(vector,double precision,integer,text) to authenticated';
    end if;
    if to_regprocedure('public.match_metabolic_knowledge(vector,double precision,integer,text)') is not null then
        execute 'grant execute on function public.match_metabolic_knowledge(vector,double precision,integer,text) to authenticated';
    end if;
    if to_regprocedure('public.match_metabolic_knowledge_multi_category(vector,double precision,integer,text[])') is not null then
        execute 'grant execute on function public.match_metabolic_knowledge_multi_category(vector,double precision,integer,text[]) to authenticated';
    end if;
end $$;
