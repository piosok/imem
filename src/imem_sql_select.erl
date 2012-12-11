-module(imem_sql_select).

-include("imem_seco.hrl").

-define(DefaultRendering, gui ).         %% gui (strings when necessary) | str (strings) | raw (erlang terms)
-define(DefaultDateFormat, eu ).         %% eu | us | iso | raw
-define(DefaultStrFormat, []).           %% escaping not implemented
-define(DefaultNumFormat, [{prec,2}]).   %% precision, no 

-export([ exec/5
        ]).

exec(SeCo, {select, SelectSections}, Stmt, _Schema, IsSec) ->
    Tables = case lists:keyfind(from, 1, SelectSections) of
        {_, TNames} ->  [imem_sql:table_qname(T) || T <- TNames];
        TError ->       ?ClientError({"Invalid select structure", TError})
    end,
    ColMap = case lists:keyfind(fields, 1, SelectSections) of
        false -> 
            imem_sql:column_map(Tables,[]);
        {_, FieldList} -> 
            imem_sql:column_map(Tables, FieldList);
        CError ->        
            ?ClientError({"Invalid select structure", CError})
    end,
    RowFun = case ?DefaultRendering of
        raw ->  imem_datatype:select_rowfun_raw(ColMap);
        str ->  imem_datatype:select_rowfun_str(ColMap, ?DefaultDateFormat, ?DefaultNumFormat, ?DefaultStrFormat);
        gui ->  imem_datatype:select_rowfun_gui(ColMap, ?DefaultDateFormat, ?DefaultNumFormat, ?DefaultStrFormat)
    end,
    MetaIdx = length(Tables) + 1,
    MetaMap = [ N || {_,N} <- lists:usort([{C#ddColMap.cind, C#ddColMap.name} || C <- ColMap, C#ddColMap.tind==MetaIdx])],

    RawMap = imem_sql:column_map(Tables,[]),
    FullMap = [Item#ddColMap{tag=list_to_atom([$$|integer_to_list(T)])} || {T,Item} <- lists:zip(lists:seq(1,length(RawMap)), RawMap)],
    io:format(user, "FullMap (~p)~n~p~n", [length(FullMap),FullMap]),
    MatchHead = list_to_tuple(['_'|[Tx || #ddColMap{tag=Tx, tind=Ti} <- FullMap, Ti==1]]),
    io:format(user, "MatchHead (~p)~n~p~n", [size(MatchHead),MatchHead]),
    Guards = case lists:keyfind(where, 1, SelectSections) of
        {_, WhereTree} ->   master_query_guards(WhereTree,FullMap);
        WError ->           ?ClientError({"Invalid where structure", WError})
    end,
    io:format(user, "Guards ~p~n", [Guards]),
    Result = '$_',
    MatchSpec = [{MatchHead, Guards, [Result]}],
    JoinSpec = [],                      %% ToDo: e.g. {join type (inner|outer|self, join field element number, matchspec joined table} per join
    Statement = Stmt#statement{
                    tables=Tables, cols=ColMap, meta=MetaMap, rowfun=RowFun,
                    matchspec=MatchSpec, joinspec=JoinSpec
                },
    {ok, StmtRef} = imem_statement:create_stmt(Statement, SeCo, IsSec),
    % io:format(user,"Statement : ~p~n", [Stmt]),
    % io:format(user,"Tables: ~p~n", [Tables]),
    % io:format(user,"Column map: ~p~n", [ColMap]),
    % io:format(user,"Meta map: ~p~n", [MetaMap]),
    % io:format(user,"MatchSpec: ~p~n", [MatchSpec]),
    % io:format(user,"JoinSpec: ~p~n", [JoinSpec]),
    {ok, ColMap, RowFun, StmtRef}.


master_query_guards([],_FullMap) -> [];
master_query_guards(WhereTree,FullMap) ->
    [tree_walk(1,WhereTree,FullMap)].

tree_walk(_,<<"true">>,_FullMap) -> true;
tree_walk(_,<<"false">>,_FullMap) -> false;
tree_walk(Ti,{'not',WC},FullMap) ->
    {'not', tree_walk(Ti,WC,FullMap)};
tree_walk(_Ti,{Op,_WC},_FullMap) -> ?UnimplementedException({"Operator not supported in where clause",Op});

tree_walk(Ti,{'=',A,B},FullMap) ->
    comparison(Ti,'==',A,B,FullMap);
tree_walk(Ti,{'<>',A,B},FullMap) ->
    comparison(Ti,'/=',A,B,FullMap);
tree_walk(Ti,{'<=',A,B},FullMap) ->
    comparison(Ti,'=<',A,B,FullMap);
tree_walk(Ti,{'>=',A,B},FullMap) ->
    comparison(Ti,'>=',A,B,FullMap);

tree_walk(Ti,{Op,WC1,WC2},FullMap) ->
    {Op, tree_walk(Ti,WC1,FullMap), tree_walk(Ti,WC2,FullMap)}.

comparison(Ti,OP,{'fun',erl,[Param]},B,FullMap) -> 
    comparison(Ti,OP,Param,B,FullMap);
comparison(Ti,OP,A, {'fun',erl,[Param]},FullMap) -> 
    comparison(Ti,OP,A,Param,FullMap);
comparison(_Ti,_OP,{'fun',A,_Params},_B,_FullMap) -> ?UnimplementedException({"Function not supported in where clause",A});
comparison(_Ti,_OP,_A,{'fun',B,_Params},_FullMap) -> ?UnimplementedException({"Function not supported in where clause",B});
comparison(Ti,OP,A,B,FullMap) when is_binary(A),is_binary(B) ->
    compguard(Ti,OP,field_lookup(A,FullMap),field_lookup(B,FullMap));
comparison(_Ti,_OP,A,B,_FullMap) when is_binary(A) -> ?UnimplementedException({"Expression not supported in where clause",B});
comparison(_Ti,_OP,A,B,_FullMap) when is_binary(B) -> ?UnimplementedException({"Expression not supported in where clause",A}).

compguard(1, _ , {A,_,_,_,_,_,_},   {B,_,_,_,_,_,_}) when A>1; B>1 -> true;   %% join condition
compguard(1, OP, {0,A,_,_,_,_,_},   {0,B,_,_,_,_,_}) ->     {OP,A,B};           
compguard(1, OP, {1,A,T,_,_,_,_},   {1,B,T,_,_,_,_}) ->     {OP,A,B};
compguard(1, _,  {1,_,AT,_,_,_,AN}, {1,_,BT,_,_,_,BN}) ->   ?ClientError({"Inconsistent field types in where clause", {{AN,AT},{BN,BT}}});
compguard(1, OP, {1,A,T,L,P,D,_},   {0,B,_,_,_,_,_}) ->     {OP,A,field_value(A,T,L,P,D,B)};
compguard(1, OP, {0,A,_,_,_,_,_},   {1,B,T,L,P,D,_}) ->     {OP,field_value(B,T,L,P,D,A),B}.

field_value(Tag,Type,Len,Prec,Def,Val) ->
    imem_datatype:value_to_db(Tag,imem_nil,Type,Len,Prec,Def,false,imem_sql:strip_quotes(Val)).

field_lookup(Name,FullMap) ->
    U = undefined,
    ML = case imem_sql:field_qname(Name) of
        {U,U,N} ->  [C || #ddColMap{name=Nam}=C <- FullMap, Nam==N];
        {U,T1,N} -> [C || #ddColMap{name=Nam,table=Tab}=C <- FullMap, (Nam==N), (Tab==T1)];
        {S,T2,N} -> [C || #ddColMap{name=Nam,table=Tab,schema=Sch}=C <- FullMap, (Nam==N), ((Tab==T2) or (Tab==U)), ((Sch==S) or (Sch==U))]
    end,
    case length(ML) of
        0 ->    {0,binary_to_list(Name),U,U,U,U,Name};
        1 ->    #ddColMap{tag=Tag,type=T,tind=Ti,length=L,precision=P,default=D} = hd(ML),
                {Ti,Tag,T,L,P,D,Name};
        _ ->    ?ClientError({"Ambiguous column name in where clause", Name})
    end.


%% --Interface functions  (calling imem_if for now, not exported) ---------

if_call_mfa(IsSec,Fun,Args) ->
    case IsSec of
        true -> apply(imem_sec,Fun,Args);
        _ ->    apply(imem_meta, Fun, lists:nthtail(1, Args))
    end.

%% TESTS ------------------------------------------------------------------

-include_lib("eunit/include/eunit.hrl").

setup() -> 
    ?imem_test_setup().

teardown(_SKey) -> 
    catch imem_meta:drop_table(def),
    ?imem_test_teardown().

db_test_() ->
    {
        setup,
        fun setup/0,
        fun teardown/1,
        {with, [
              fun test_without_sec/1
            , fun test_with_sec/1
        ]}
    }.
    
test_without_sec(_) -> 
    test_with_or_without_sec(false).

test_with_sec(_) ->
    test_with_or_without_sec(true).

test_with_or_without_sec(IsSec) ->
    try
        % ClEr = 'ClientError',
        % SeEx = 'SecurityException',
        io:format(user, "----TEST--- ~p ----Security ~p ~n", [?MODULE, IsSec]),

        io:format(user, "schema ~p~n", [imem_meta:schema()]),
        io:format(user, "data nodes ~p~n", [imem_meta:data_nodes()]),
        ?assertEqual(true, is_atom(imem_meta:schema())),
        ?assertEqual(true, lists:member({imem_meta:schema(),node()}, imem_meta:data_nodes())),

        SKey=case IsSec of
            true ->     ?imem_test_admin_login();
            false ->    none
        end,

        ?assertEqual(ok, imem_sql:exec(SKey, "
                create table def (
                    col1 integer, 
                    col2 char(2), 
                    col3 date default fun() -> calendar:local_time() end.
                );", 0, 'Imem', IsSec)),

        ?assertEqual(ok, insert_range(SKey, 10, "def", 'Imem', IsSec)),

        Result0 = if_call_mfa(IsSec,select,[SKey, ddTable, ?MatchAllRecords, 1000]),
        {List0, true} = Result0,
        io:format(user, "ddTable MatchAllRecords (~p)~n~p~n...~n~p~n", [length(List0),hd(List0),lists:last(List0)]),
        AllTableCount = length(List0),

        Result1 = if_call_mfa(IsSec,select,[SKey, all_tables, ?MatchAllKeys]),
        {List1, true} = Result1,
        io:format(user, "all_tables MatchAllKeys (~p)~n~p~n", [length(List1),List1]),
        ?assertEqual(AllTableCount, length(List1)),

        Result2 = if_call_mfa(IsSec,select,[SKey, def, ?MatchAllRecords, 1000]),
        {List2, true} = Result2,
        io:format(user, "def MatchAllRecords (~p)~n~p~n...~n~p~n", [length(List2),hd(List2),lists:last(List2)]),

        Sql6 = "select col1, col2 from def where col1>=5 and col1<=8",
        io:format(user, "Query: ~p~n", [Sql6]),
        {ok, _Clm6, RowFun6, StmtRef6} = imem_sql:exec(SKey, Sql6, 100, 'Imem', IsSec),
        ?assertEqual(ok, imem_statement:fetch_recs_async(SKey, StmtRef6, self(), IsSec)),
        Result6 = receive 
            R6 ->    R6
        end,
        {List6, true} = Result6,
        io:format(user, "Result: (~p)~n~p~n", [length(List6),lists:map(RowFun6,List6)]),
        ?assertEqual(4, length(List6)),

        Sql3 = "select qname from Imem.ddTable",
        io:format(user, "Query: ~p~n", [Sql3]),
        {ok, _Clm3, RowFun3, StmtRef3} = imem_sql:exec(SKey, Sql3, 100, 'Imem', IsSec),  %% all_tables
        ?assertEqual(ok, imem_statement:fetch_recs_async(SKey, StmtRef3, self(), IsSec)),
        Result3 = receive 
            R3 ->    R3
        end,
        {List3, true} = Result3,
        io:format(user, "Result: (~p)~n~p~n", [length(List3),lists:map(RowFun3,List3)]),
        ?assertEqual(AllTableCount, length(List3)),

        ?assertEqual(ok, imem_statement:fetch_recs_async(SKey, StmtRef3, self(), IsSec)),
        Result3a = receive 
            R3a ->    R3a
        end,
        {List3a, true} = Result3a,
        io:format(user, "Result: (~p) reread~n~p~n", [length(List3a),lists:map(RowFun3,List3a)]),
        ?assertEqual(AllTableCount, length(List3a)),

%        Sql4 = "select all_tables.* from all_tables where qname = erl(\"{'Imem',ddRole}")",
        Sql4 = "select all_tables.* from all_tables where owner = undefined",
        io:format(user, "Query: ~p~n", [Sql4]),
        {ok, _Clm4, RowFun4, StmtRef4} = imem_sql:exec(SKey, Sql4, 100, 'Imem', IsSec),  %% all_tables
        ?assertEqual(ok, imem_statement:fetch_recs_async(SKey, StmtRef4, self(), IsSec)),
        Result4 = receive 
            R4 ->    R4
        end,
        {List4, true} = Result4,
        io:format(user, "Result: (~p)~n~p~n", [length(List4),lists:map(RowFun4,List4)]),
        case IsSec of
            false -> ?assertEqual(1, length(List4));
            true ->  ?assertEqual(0, length(List4))
        end,

        Sql5 = "select col1, col2, col3, user from def where 1=1 and col2 = \"7\"",
        io:format(user, "Query: ~p~n", [Sql5]),
        {ok, _Clm5, RowFun5, StmtRef5} = imem_sql:exec(SKey, Sql5, 100, 'Imem', IsSec),
        ?assertEqual(ok, imem_statement:fetch_recs_async(SKey, StmtRef5, self(), IsSec)),
        Result5 = receive 
            R5 ->    R5
        end,
        {List5, true} = Result5,
        io:format(user, "Result: (~p)~n~p~n", [length(List5),lists:map(RowFun5,List5)]),
        ?assertEqual(1, length(List5)),            

        ?assertEqual(ok, imem_statement:close(SKey, StmtRef3)),
        ?assertEqual(ok, imem_statement:close(SKey, StmtRef4)),
        ?assertEqual(ok, imem_statement:close(SKey, StmtRef5)),

        ?assertEqual(ok, imem_sql:exec(SKey, "drop table def;", 0, 'Imem', IsSec)),

        case IsSec of
            true ->     ?imem_logout(SKey);
            false ->    ok
        end

    catch
        Class:Reason ->  io:format(user, "Exception ~p:~p~n~p~n", [Class, Reason, erlang:get_stacktrace()]),
        ?assert( true == "all tests completed")
    end,
    ok. 



insert_range(_SKey, 0, _TableName, _Schema, _IsSec) -> ok;
insert_range(SKey, N, TableName, Schema, IsSec) when is_integer(N), N > 0 ->
    imem_sql:exec(SKey, "insert into " ++ TableName ++ " (col1, col2) values (" ++ integer_to_list(N) ++ ", '" ++ integer_to_list(N) ++ "');", 0, Schema, IsSec),
    insert_range(SKey, N-1, TableName, Schema, IsSec).