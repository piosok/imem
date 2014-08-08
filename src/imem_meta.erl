-module(imem_meta).

%% @doc == imem metadata and table management ==
%% Naming conventions for sharded/partitioned tables
%% Table creation / Index table creation
%% Triggers and validator funs
%% Virtual tables  


-include("imem.hrl").
-include("imem_meta.hrl").

%% HARD CODED CONFIGURATIONS

-define(DDNODE_TIMEOUT,3000).       %% RPC timeout for ddNode evaluation

-define(META_TABLES,[?CACHE_TABLE,?LOG_TABLE,?MONITOR_TABLE,dual,ddNode,ddSchema,ddSize,ddAlias,ddTable]).
-define(META_FIELDS,[<<"rownum">>,<<"systimestamp">>,<<"user">>,<<"username">>,<<"sysdate">>,<<"schema">>,<<"node">>]). 
-define(META_OPTS,[purge_delay,trigger]). % table options only used in imem_meta and above

-define(CONFIG_TABLE_OPTS,  [{record_name,ddConfig}
                            ,{type,ordered_set}
                            ]).          

-define(LOG_TABLE_OPTS,     [{record_name,ddLog}
                            ,{type,ordered_set}
                            ,{purge_delay,430000}        %% 430000 = 5 Days - 2000 sec
                            ]).          

-define(ddTableTrigger,     <<"fun(__OR,__NR,__T,__U) -> imem_meta:dictionary_trigger(__OR,__NR,__T,__U) end.">> ).
-define(DD_ALIAS_OPTS,      [{trigger,?ddTableTrigger}]).          
-define(DD_TABLE_OPTS,      [{trigger,?ddTableTrigger}]).
-define(DD_CACHE_OPTS,      [{scope,local}
                            ,{local_content,true}
                            ,{record_name,ddCache}
                            ]).          
-define(DD_INDEX_OPTS,      [{record_name,ddIndex}
                            ,{type,ordered_set}         %% ,{purge_delay,430000}  %% inherit from parent table
                            ]).          

-define(BAD_NAME_CHARACTERS,"!?#*:+-.\\<|>/").  %% invalid chars for tables and columns

% -define(RecIdx, 1).                                       %% Record name position in records
% -define(FirstIdx, 2).                                     %% First field position in records
-define(KeyIdx, 2).                                       %% Key position in records


%% DEFAULT CONFIGURATIONS ( overridden in table ddConfig)

-behavior(gen_server).

-record(state, {}).

-export([ start_link/1
        ]).

% gen_server behavior callbacks
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        , format_status/2
        , fail/1
        ]).


-export([ drop_meta_tables/0
        , drop_system_table/1
        ]).

-export([ schema/0
        , schema/1
        , system_id/0
        , data_nodes/0
        , host_fqdn/1
        , host_name/1
        , node_name/1
        , node_hash/1
        , all_aliases/0
        , all_tables/0
        , tables_starting_with/1
        , tables_ending_with/1
        , node_shard/0
        , qualified_table_name/1
        , qualified_new_table_name/1
        , physical_table_name/1
        , physical_table_name/2
        , physical_table_names/1
        , partitioned_table_name_str/2
        , partitioned_table_name/2
        , parse_table_name/1
        , is_system_table/1
        , is_readable_table/1
        , is_virtual_table/1
        , is_time_partitioned_alias/1
        , is_local_time_partitioned_table/1
        , is_node_sharded_alias/1
        , is_local_node_sharded_table/1
        , time_of_partition_expiry/1
        , time_to_partition_expiry/1
        , table_type/1
        , table_columns/1
        , table_size/1
        , table_memory/1
        , table_record_name/1        
        , trigger_infos/1
        , dictionary_trigger/4
        , check_table/1
        , check_table_meta/2
        , check_table_columns/2
        , meta_field_list/0        
        , meta_field/1
        , meta_field_info/1
        , meta_field_value/1
        , column_infos/1
        , from_column_infos/1
        , column_info_items/2
        ]).

-export([ add_attribute/2
        , update_opts/2
        , compile_fun/1
        , log_to_db/5
        , log_to_db/6
        , log_to_db/7
        , log_slow_process/6
        , failing_function/1
        , get_config_hlk/5
        , put_config_hlk/6
        ]).

-export([ init_create_table/3
        , init_create_table/4
        , init_create_check_table/3
        , init_create_check_table/4
        , init_create_trigger/2
        , init_create_or_replace_trigger/2
        , init_create_index/2
        , init_create_or_replace_index/2
        , create_table/3
        , create_table/4
        , create_partitioned_table/2
        , create_partitioned_table_sync/2
        , create_check_table/3
        , create_check_table/4
        , create_trigger/2
        , create_or_replace_trigger/2
        , create_index/2
        , create_or_replace_index/2
        , create_sys_conf/1
        , drop_table/1
        , drop_trigger/1
        , drop_index/1
        , purge_table/1
        , purge_table/2
        , truncate_table/1
        , truncate_table/2
        , snapshot_table/1  %% dump local table to snapshot directory
        , restore_table/1   %% replace local table by version in snapshot directory
        , read/1            %% read whole table, only use for small tables 
        , read/2            %% read by key
        , read_hlk/2        %% read using hierarchical list key
        , select/2          %% select without limit, only use for small result sets
        , select_virtual/2  %% select virtual table without limit, only use for small result sets
        , select/3          %% select with limit
        , select_sort/2
        , select_sort/3
        , modify/7          %% parameterized insert/update/merge/remove
        , insert/2          %% apply defaults, write row if key does not exist, apply trigger
        , insert/3          %% apply defaults, write row if key does not exist, apply trigger
        , update/2          %% apply defaults, write row if key exists, apply trigger (bags not supported)
        , update/3          %% apply defaults, write row if key exists, apply trigger (bags not supported)
        , merge/2           %% apply defaults, write row, apply trigger (bags not supported)
        , merge/3           %% apply defaults, write row, apply trigger (bags not supported)
        , remove/2          %% delete row if key exists (if bag row exists), apply trigger
        , remove/3          %% delete row if key exists (if bag row exists), apply trigger
        , write/2           %% write row for single key, no defaults applied, no trigger applied
        , write_log/1
        , dirty_read/2
        , dirty_write/2
        , delete/2          %% delete row by key
        , delete_object/2   %% delete single row in bag table 
        ]).

-export([ update_prepare/3          %% stateless creation of update plan from change list
        , update_cursor_prepare/2   %% take change list and generate update plan (stored in state)
        , update_cursor_execute/2   %% take update plan from state and execute it (fetch aborted first)
        , apply_defaults/2          %% apply arity/0 funs of default record to ?nav values of current record
        , apply_validators/3        %% apply any arity funs of default record to current record
        , apply_validators/4        %% apply any arity funs of default record to current record
        , fetch_recs/3
        , fetch_recs_sort/3 
        , fetch_recs_async/2        
        , fetch_recs_async/3 
        , filter_and_sort/3       
        , filter_and_sort/4       
        , fetch_close/1
        , exec/3
        , close/1
        ]).

-export([ fetch_start/5
        , update_tables/2
        , update_index/5            %% (Old,New,Tab,User,IdxDef)   
        , update_bound_counter/6
        , subscribe/1
        , unsubscribe/1
        ]).

-export([ transaction/1
        , transaction/2
        , transaction/3
        , return_atomic_list/1
        , return_atomic_ok/1
        , return_atomic/1
        , foldl/3
        , lock/2
        ]).

-export([ simple_or_local_node_sharded_tables/1]).


start_link(Params) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Params, [{spawn_opt, [{fullsweep_after, 0}]}]).

init_create_table(TableName,RecDef,Opts) ->
    init_create_table(TableName,RecDef,Opts,#ddTable{}#ddTable.owner).

init_create_table(TableName,RecDef,Opts,Owner) ->
    case (catch create_table(TableName, RecDef, Opts, Owner)) of
        {'ClientError',{"Table already exists", _}} = R ->   
            ?Info("creating ~p results in ~p", [TableName,"Table already exists"]),
            R;
        {'ClientError',Reason}=Res ->   
            ?Info("creating ~p results in ~p", [TableName,Reason]),
            Res;
        Result ->                   
            ?Info("creating ~p results in ~p", [TableName,Result]),
            Result
    end.

init_create_check_table(TableName,RecDef,Opts) ->
    init_create_check_table(TableName,RecDef,Opts,#ddTable{}#ddTable.owner).

init_create_check_table(TableName,RecDef,Opts,Owner) ->
    case (catch create_check_table(TableName, RecDef, Opts, Owner)) of
        {'ClientError',{"Table already exists", _}} = R ->   
            ?Info("creating ~p results in ~p", [TableName,"Table already exists"]),
            R;
        {'ClientError',Reason}=Res ->   
            ?Info("creating ~p results in ~p", [TableName,Reason]),
            Res;
        Result ->                   
            ?Info("creating ~p results in ~p", [TableName,Result]),
            Result
    end.

init_create_trigger(TableName,TriggerStr) ->
    case (catch create_trigger(TableName,TriggerStr)) of
        {'ClientError',{"Trigger already exists",{Table,_}}} = Res ->   
            ?Info("creating trigger for ~p results in ~p", [Table,"Trigger exists in different version"]),
            Res;
        {'ClientError',{"Trigger already exists", Table}} = R ->   
            ?Info("creating trigger for ~p results in ~p", [Table,"Trigger already exists"]),
            R;
        Result ->                   
            ?Info("creating trigger for ~p results in ~p", [TableName,Result]),
            Result
    end.


init_create_or_replace_trigger(TableName,TriggerStr) ->
    case (catch create_or_replace_trigger(TableName,TriggerStr)) of
        Result ->                   
            ?Info("creating trigger for ~p results in ~p", [TableName,Result]),
            Result
    end.

init_create_index(TableName,IndexDefinition) when is_list(IndexDefinition) ->
    case (catch create_index(TableName,IndexDefinition)) of
        {'ClientError',{"Index already exists",{Table,_}}} = Res ->   
            ?Info("creating index for ~p results in ~p", [Table,"Index exists in different version"]),
            Res;
        {'ClientError',{"Index already exists", Table}} = R ->   
            ?Info("creating index for ~p results in ~p", [Table,"Index already exists"]),
            R;
        Result ->                   
            ?Info("creating index for ~p results in ~p", [TableName,Result]),
            Result
    end.

init_create_or_replace_index(TableName,IndexDefinition) when is_list(IndexDefinition) ->
    case (catch create_or_replace_index(TableName,IndexDefinition)) of
        Result ->                   
            ?Info("creating index for ~p results in ~p", [TableName,Result]),
            Result
    end.

init(_Args) ->
    ?Info("~p starting...~n", [?MODULE]),
    Result = try
        application:set_env(imem, node_shard, node_shard()),

        init_create_table(ddAlias, {record_info(fields, ddAlias),?ddAlias,#ddAlias{}}, ?DD_ALIAS_OPTS, system),         %% may not be able to register in ddTable
        init_create_table(?CACHE_TABLE, {record_info(fields, ddCache), ?ddCache, #ddCache{}}, ?DD_CACHE_OPTS, system),  %% may not be able to register in ddTable
        init_create_table(ddTable, {record_info(fields, ddTable),?ddTable,#ddTable{}}, ?DD_TABLE_OPTS, system),
        init_create_table(?CACHE_TABLE, {record_info(fields, ddCache), ?ddCache, #ddCache{}}, ?DD_CACHE_OPTS, system),  %% register in ddTable if not done yet
        init_create_table(ddAlias, {record_info(fields, ddAlias),?ddAlias,#ddAlias{}}, ?DD_ALIAS_OPTS, system),         %% register in ddTable if not done yet 
        catch check_table(ddTable),
        catch check_table_columns(ddTable, record_info(fields, ddTable)),
        catch check_table_meta(ddTable, {record_info(fields, ddTable), ?ddTable, #ddTable{}}),

        init_create_check_table(ddNode, {record_info(fields, ddNode),?ddNode,#ddNode{}}, [], system),    
        init_create_check_table(ddSchema, {record_info(fields, ddSchema),?ddSchema, #ddSchema{}}, [], system),    
        init_create_check_table(ddSize, {record_info(fields, ddSize),?ddSize, #ddSize{}}, [], system),    
        init_create_check_table(?CONFIG_TABLE, {record_info(fields, ddConfig),?ddConfig, #ddConfig{}}, ?CONFIG_TABLE_OPTS, system),
        init_create_check_table(?LOG_TABLE, {record_info(fields, ddLog), ?ddLog, #ddLog{}}, ?LOG_TABLE_OPTS, system),    
        init_create_table(dual, {record_info(fields, dual),?dual, #dual{}}, [], system),
        write(dual,#dual{}),

        init_create_trigger(ddTable, ?ddTableTrigger),

        ?Info("~p started!~n", [?MODULE]),
        {ok,#state{}}
    catch
        _Class:Reason -> {stop, {Reason,erlang:get_stacktrace()}} 
    end,
    Result.

create_partitioned_table_sync(TableAlias,TableName) when is_atom(TableAlias), is_atom(TableName) ->
    ImemMetaPid = erlang:whereis(?MODULE),
    case self() of
        ImemMetaPid ->
            {error,recursive_call};   %% cannot call myself
        _ ->
            gen_server:call(?MODULE, {create_partitioned_table, TableAlias, TableName},35000)
    end. 

create_partitioned_table(TableAlias, TableName) when is_atom(TableName) ->
    try 
        case imem_if:read(ddTable,{schema(), TableName}) of
            [#ddTable{}] ->
                % Table seems to exist, may need to load it
                case catch(check_table(TableName)) of
                    ok ->   ok;
                    {'ClientError',{"Table does not exist",TableName}} ->
                        create_nonexisting_partitioned_table(TableAlias,TableName);
                    Res ->
                        ?Info("Waiting for partitioned table ~p needed because of ~p", [TableName,Res]),
                        case mnesia:wait_for_tables([TableName], 30000) of
                            ok ->   ok;   
                            Error ->            
                                ?Error("Waiting for partitioned table failed with ~p", [Error]),
                                {error,Error}
                        end
                end;
            [] ->
                % Table does not exist in ddTable, must create it similar to existing
                create_nonexisting_partitioned_table(TableAlias,TableName)   
        end
    catch
        _:Reason1 ->
            ?Error("Create partitioned table failed with ~p", [Reason1]),
            {error,Reason1}
    end.

create_nonexisting_partitioned_table(TableAlias, TableName) ->
    % find out ColumnsInfos, Opts, Owner from ddAlias
    case imem_if:read(ddAlias,{schema(), TableAlias}) of
        [] ->
            ?Error("Table template not found in ddAlias~p", [TableAlias]),   
            {error, {"Table template not found in ddAlias", TableAlias}}; 
        [#ddAlias{columns=ColumnInfos,opts=Opts,owner=Owner}] ->
            try
                create_table(TableName, ColumnInfos, Opts, Owner)
            catch
                _:Reason2 -> {error, Reason2}
            end
    end.

handle_call({create_partitioned_table, TableAlias, TableName}, _From, State) ->
    {reply, create_partitioned_table(TableAlias,TableName), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%     {stop,{shutdown,Reason},State};
% handle_cast({stop, Reason}, State) ->
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reson, _State) -> ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, [_PDict, _State]) -> ok.

fail(Reason) ->
    throw(Reason).

dictionary_trigger(OldRec,NewRec,T,_User) when T==ddTable; T==ddAlias ->
    %% clears cached trigger information when ddTable is 
    %% modified in GUI or with insert/update/merge/remove functions
    case {OldRec,NewRec} of
        {{},{}} ->  %% truncate ddTable/ddAlias should never happen, allow for recovery operations
            ok;          
        {{},_}  ->  %% write new rec (maybe fixing something)
            {S,TN} = element(2,NewRec),
            imem_cache:clear({?MODULE, trigger, S, TN});
        {_,_}  ->  %% update old rec (maybe fixing something)
            {S,TO} = element(2,OldRec),
            imem_cache:clear({?MODULE, trigger, S, TO})
    end.

%% ------ META implementation -------------------------------------------------------


% is_system_table({_S,Table,_A}) -> is_system_table(Table);   % TODO: May depend on Schema
is_system_table({_,Table}) -> 
    is_system_table(Table);       % TODO: May depend on Schema
is_system_table(Table) when is_atom(Table) ->
    case lists:member(Table,?META_TABLES) of
        true ->     true;
        false ->    imem_if:is_system_table(Table)
    end;
is_system_table(Table) when is_binary(Table) ->
    try
        {S,T} = imem_sql_expr:binstr_to_qname2(Table), 
        is_system_table({?binary_to_existing_atom(S),?binary_to_existing_atom(T)})
    catch
        _:_ -> false
    end.

check_table(Table) when is_atom(Table) ->
    imem_if:table_size(physical_table_name(Table)),
    ok;
check_table({ddSysConf, _Table}) -> ok.


check_table_meta({ddSysConf, _}, _) -> ok;
check_table_meta(TableAlias, {Names, Types, DefaultRecord}) when is_atom(TableAlias) ->
    [_|Defaults] = tuple_to_list(DefaultRecord),
    ColumnInfos = column_infos(Names, Types, Defaults),
    case imem_if:read(ddTable,{schema(), physical_table_name(TableAlias)}) of
        [] ->   ?SystemException({"Missing table metadata",TableAlias}); 
        [#ddTable{columns=ColumnInfos}] ->
            CINames = column_info_items(ColumnInfos, name),
            CITypes = column_info_items(ColumnInfos, type),
            CIDefaults = column_info_items(ColumnInfos, default),
            if
                (CINames =:= Names) andalso (CITypes =:= Types) andalso (CIDefaults =:= Defaults) ->  
                    ok;
                true ->                 
                    ?SystemException({"Record does not match table metadata",TableAlias})
            end;
        Else -> 
            ?SystemException({"Column definition does not match table metadata",{TableAlias,Else}})    
    end;  
check_table_meta(TableAlias, ColumnNames) when is_atom(TableAlias) ->
    case imem_if:read(ddTable,{schema(), physical_table_name(TableAlias)}) of
        [] ->   ?SystemException({"Missing table metadata",TableAlias}); 
        [#ddTable{columns=ColumnInfo}] ->
            CINames = column_info_items(ColumnInfo, name),
            if
                CINames =:= ColumnNames ->  
                    ok;
                true ->                 
                    ?SystemException({"Record field names do not match table metadata",TableAlias})
            end          
    end.

check_table_columns({ddSysConf, _}, _) -> ok;
check_table_columns(TableAlias, {Names, Types, DefaultRecord}) when is_atom(TableAlias) ->
    [_|Defaults] = tuple_to_list(DefaultRecord),
    ColumnInfo = column_infos(Names, Types, Defaults),
    TableColumns = table_columns(TableAlias),    
    MetaInfo = column_infos(TableAlias),    
    if
        Names /= TableColumns ->
            ?SystemException({"Column names do not match table structure",TableAlias});             
        ColumnInfo /= MetaInfo ->
            ?SystemException({"Column info does not match table metadata",TableAlias});
        true ->     ok
    end;
check_table_columns(TableAlias, [CI|_]=ColumnInfo) when is_atom(TableAlias), is_tuple(CI) ->
    ColumnNames = column_info_items(ColumnInfo, name),
    TableColumns = table_columns(TableAlias),
    MetaInfo = column_infos(TableAlias),    
    if
        ColumnNames /= TableColumns ->
            ?SystemException({"Column info does not match table structure",TableAlias}) ;
        ColumnInfo /= MetaInfo ->
            ?SystemException({"Column info does not match table metadata",TableAlias});
        true ->     ok                           
    end;
check_table_columns(TableAlias, ColumnNames) when is_atom(TableAlias) ->
    TableColumns = table_columns(TableAlias),
    if
        ColumnNames /= TableColumns ->
            ?SystemException({"Column info does not match table structure",TableAlias}) ;
        true ->     ok                           
    end.

drop_meta_tables() ->
    drop_meta_tables(?META_TABLES).

drop_meta_tables([]) -> ok;
drop_meta_tables([TableAlias|Tables]) ->
    drop_system_table(TableAlias),
    drop_meta_tables(Tables).

meta_field_list() -> ?META_FIELDS.

meta_field(Name) when is_atom(Name) ->
    meta_field(?atom_to_binary(Name));
meta_field(Name) ->
    lists:member(Name,?META_FIELDS).

meta_field_info(Name) when is_atom(Name) ->
    meta_field_info(?atom_to_binary(Name));
meta_field_info(<<"sysdate">>=N) ->
    #ddColumn{name=N, type='datetime', len=20, prec=0};
meta_field_info(<<"systimestamp">>=N) ->
    #ddColumn{name=N, type='timestamp', len=20, prec=0};
meta_field_info(<<"schema">>=N) ->
    #ddColumn{name=N, type='atom', len=10, prec=0};
meta_field_info(<<"node">>=N) ->
    #ddColumn{name=N, type='atom', len=30, prec=0};
meta_field_info(<<"user">>=N) ->
    #ddColumn{name=N, type='userid', len=20, prec=0};
meta_field_info(<<"username">>=N) ->
    #ddColumn{name=N, type='binstr', len=20, prec=0};
meta_field_info(<<"rownum">>=N) ->
    #ddColumn{name=N, type='integer', len=10, prec=0};
meta_field_info(Name) ->
    ?ClientError({"Unknown meta column",Name}). 

meta_field_value(<<"rownum">>) ->   1; 
meta_field_value(rownum) ->         1; 
meta_field_value(<<"username">>) -> <<"unknown">>; 
meta_field_value(username) ->       <<"unknown">>; 
meta_field_value(<<"user">>) ->     unknown; 
meta_field_value(user) ->           unknown; 
meta_field_value(Name) ->
    imem_if:meta_field_value(Name). 

column_info_items(Info, name) ->
    [C#ddColumn.name || C <- Info];
column_info_items(Info, type) ->
    [C#ddColumn.type || C <- Info];
column_info_items(Info, default) ->
    [C#ddColumn.default || C <- Info];
column_info_items(Info, default_fun) ->
    lists:map(fun imem_datatype:to_term_or_fun/1, [C#ddColumn.default || C <- Info]);
column_info_items(Info, len) ->
    [C#ddColumn.len || C <- Info];
column_info_items(Info, prec) ->
    [C#ddColumn.prec || C <- Info];
column_info_items(Info, opts) ->
    [C#ddColumn.opts || C <- Info];
column_info_items(_Info, Item) ->
    ?ClientError({"Invalid item",Item}).

column_names(Infos)->
    [list_to_atom(lists:flatten(io_lib:format("~p", [N]))) || #ddColumn{name=N} <- Infos].

column_infos(TableAlias) when is_atom(TableAlias) ->
    column_infos({schema(),TableAlias});    
column_infos({Schema,TableAlias}) when is_binary(Schema), is_binary(TableAlias) ->
    S= try 
        ?binary_to_existing_atom(Schema)
    catch 
        _:_ -> ?ClientError({"Schema does not exist",Schema})
    end,
    T = try 
        ?binary_to_existing_atom(TableAlias)
    catch 
        _:_ -> ?ClientError({"Table does not exist",TableAlias})
    end,        
    column_infos({S,T});
column_infos({Schema,TableAlias}) when is_atom(Schema), is_atom(TableAlias) ->
    case lists:member(TableAlias, ?DataTypes) of
        true -> 
            [#ddColumn{name=item, type=TableAlias, len=0, prec=0, default=undefined}];
        false ->
            case imem_if:read(ddTable,{Schema, physical_table_name(TableAlias)}) of
                [] ->                       ?ClientError({"Table does not exist",{Schema,TableAlias}}); 
                [#ddTable{columns=CI}] ->   CI
            end
    end;  
column_infos(Names) when is_list(Names)->
    [#ddColumn{name=list_to_atom(lists:flatten(io_lib:format("~p", [N])))} || N <- Names].

column_infos(Names, Types, Defaults)->
    NamesLength = length(Names),
    TypesLength = length(Types),
    DefaultsLength = length(Defaults),
    if (NamesLength =/= TypesLength)
       orelse (NamesLength =/= DefaultsLength)
       orelse (TypesLength =/= DefaultsLength) ->
        ?ClientError({"Column definition params length mismatch", { {"Names", NamesLength}
                                                             , {"Types", TypesLength}
                                                             , {"Defaults", DefaultsLength}}});
    true -> ok
    end,
    [#ddColumn{name=list_to_atom(lists:flatten(io_lib:format("~p", [N]))), type=T, default=D} || {N,T,D} <- lists:zip3(Names, Types, Defaults)].

from_column_infos([#ddColumn{}|_] = ColumnInfos) ->
    ColumnNames = column_info_items(ColumnInfos, name),
    ColumnTypes = column_info_items(ColumnInfos, type),
    DefaultRecord = list_to_tuple([rec|column_info_items(ColumnInfos, default)]),
    {ColumnNames, ColumnTypes, DefaultRecord}.

create_table(TableAlias, Columns, Opts) ->
    create_table(TableAlias, Columns, Opts, #ddTable{}#ddTable.owner).

create_table(TableAlias, {ColumnNames, ColumnTypes, DefaultRecord}, Opts, Owner) ->
    [_|Defaults] = tuple_to_list(DefaultRecord),
    ColumnInfos = column_infos(ColumnNames, ColumnTypes, Defaults),
    create_physical_table(TableAlias,ColumnInfos,Opts,Owner);
create_table(TableAlias, [#ddColumn{}|_]=ColumnInfos, Opts, Owner) ->
    Conv = fun(X) ->
        case X#ddColumn.name of
            A when is_atom(A) -> X; 
            B -> X#ddColumn{name=?binary_to_atom(B)} 
        end
    end,
    create_physical_table(qualified_new_table_name(TableAlias),lists:map(Conv,ColumnInfos),Opts,Owner);
create_table(TableAlias, ColumnNames, Opts, Owner) ->
    ColumnInfos = column_infos(ColumnNames),
    create_physical_table(TableAlias,ColumnInfos,Opts,Owner).

create_check_table(TableAlias, Columns, Opts) ->
    create_check_table(TableAlias, Columns, Opts, (#ddTable{})#ddTable.owner).

create_check_table(TableAlias, [#ddColumn{}|_]=ColumnInfos, Opts, Owner) ->
    Conv = fun(X) ->
        case X#ddColumn.name of
            A when is_atom(A) -> X; 
            B -> X#ddColumn{name=?binary_to_atom(B)} 
        end
    end,
    {ColumnNames, ColumnTypes, DefaultRecord} = from_column_infos(lists:map(Conv,ColumnInfos)),
    create_check_table(qualified_new_table_name(TableAlias), {ColumnNames, ColumnTypes, DefaultRecord}, Opts, Owner);
create_check_table(TableAlias, {ColumnNames, ColumnTypes, DefaultRecord}, Opts, Owner) ->
    [_|Defaults] = tuple_to_list(DefaultRecord),
    ColumnInfos = column_infos(ColumnNames, ColumnTypes, Defaults),
    create_check_physical_table(TableAlias,ColumnInfos,Opts,Owner),
    check_table(TableAlias),
    check_table_columns(TableAlias, ColumnNames),
    check_table_meta(TableAlias, {ColumnNames, ColumnTypes, DefaultRecord}).

create_sys_conf(Path) ->
    imem_if_sys_conf:create_sys_conf(Path).    

create_check_physical_table(TableAlias,ColumnInfos,Opts,Owner) when is_atom(TableAlias) ->
    create_check_physical_table({schema(),TableAlias},ColumnInfos,Opts,Owner);    
create_check_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner) ->
    MySchema = schema(),
    case lists:member(Schema, [MySchema, ddSysConf]) of
        true ->
            PhysicalName=physical_table_name(TableAlias),
            case read(ddTable,{Schema,PhysicalName}) of 
                [] ->
                    create_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner);
                [#ddTable{opts=Opts,owner=Owner}] ->
                    catch create_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner),
                    ok;
                [#ddTable{opts=Old,owner=Owner}] ->
                    OldOpts = lists:sort(lists:keydelete(purge_delay,1,Old)),
                    NewOpts = lists:sort(lists:keydelete(purge_delay,1,Opts)),
                    case NewOpts of
                        OldOpts ->
                            catch create_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner),
                            ok;
                        _ ->
                            catch create_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner), 
                            ?SystemException({"Wrong table options",{TableAlias,Old}})
                    end;        
                [#ddTable{owner=Own}] ->
                    catch create_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner),
                    ?SystemException({"Wrong table owner",{TableAlias,Own}})        
            end;
        _ ->        
            ?UnimplementedException({"Create/check table in foreign schema",{Schema,TableAlias}})
    end.

create_physical_table({Schema,TableAlias,_Alias},ColumnInfos,Opts,Owner) ->
    create_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner);
create_physical_table({Schema,TableAlias},ColumnInfos,Opts,Owner) ->
    MySchema = schema(),
    case Schema of
        MySchema -> create_physical_table(TableAlias,ColumnInfos,Opts,Owner);
        ddSysConf -> create_table_sys_conf(TableAlias, ColumnInfos, Opts, Owner);
        _ ->    ?UnimplementedException({"Create table in foreign schema",{Schema,TableAlias}})
    end;
create_physical_table(TableAlias,ColInfos,Opts,Owner) ->
    case is_valid_table_name(TableAlias) of
        true ->     ok;
        false ->    ?ClientError({"Invalid character(s) in table name",TableAlias})
    end,    
    case sqlparse:is_reserved(TableAlias) of
        false ->    ok;
        true ->     ?ClientError({"Reserved table name",TableAlias})
    end,
    case length(ColInfos) of
        0 ->    ?ClientError({"No columns given in create table",TableAlias});
        1 ->    ?ClientError({"No value column given in create table, add dummy value column",TableAlias});
        _ ->    ok
    end,
    CharsCheck = [{is_valid_column_name(Name),Name} || Name <- column_info_items(ColInfos, name)],
    case lists:keyfind(false, 1, CharsCheck) of
        false ->    ok;
        {_,BadN} -> ?ClientError({"Invalid character(s) in column name",BadN})
    end,
    ReservedCheck = [{sqlparse:is_reserved(Name),Name} || Name <- column_info_items(ColInfos, name)],
    case lists:keyfind(true, 1, ReservedCheck) of
        false ->    ok;
        {_,BadC} -> ?ClientError({"Reserved column name",BadC})
    end,
    TypeCheck = [{imem_datatype:is_datatype(Type),Type} || Type <- column_info_items(ColInfos, type)],
    case lists:keyfind(false, 1, TypeCheck) of
        false ->    ok;
        {_,BadT} -> ?ClientError({"Invalid data type",BadT})
    end,
    FunCheck = [{imem_datatype:is_term_or_fun_text(Def),Def} || Def <- column_info_items(ColInfos, default)],
    case lists:keyfind(false, 1, FunCheck) of
        false ->    ok;
        {_,BadDef} -> ?ClientError({"Invalid default fun",BadDef})
    end,
    TableName=physical_table_name(TableAlias),
    DDTableRow = #ddTable{qname={schema(),TableName}, columns=ColInfos, opts=Opts, owner=Owner},
    DDAliasRow = #ddAlias{qname={schema(),TableAlias}, columns=ColInfos, opts=Opts, owner=Owner},
    case TableName of
        TA when TA==ddAlias;TA==?CACHE_TABLE ->  
            % ?Info("creating table with opts ~p ~p ~n", [TA,if_opts(Opts)]),
            case (catch imem_if:read(ddTable, {schema(),TableName})) of
                [] ->   
                    imem_if:write(ddTable, DDTableRow),
                    catch (imem_if:create_table(TableName, column_names(ColInfos), if_opts(Opts) ++ [{user_properties, [DDTableRow]}]));    % ddTable meta data is missing
                _ ->    
                    imem_if:create_table(TableName, column_names(ColInfos), if_opts(Opts) ++ [{user_properties, [DDTableRow]}])                                      % entry exists or ddTable does not exists yet
            end,
            
            imem_cache:clear({?MODULE, trigger, schema(), TableName});
        TableAlias ->
            try
                % ?Info("creating table with opts ~p ~p ~n", [TableName,if_opts(Opts)]),
                imem_if:create_table(TableName, column_names(ColInfos), if_opts(Opts) ++ [{user_properties, [DDTableRow]}]),
                imem_if:write(ddTable, DDTableRow)
            catch
                _:{'ClientError',{"Table already exists",TableName}} = Reason ->
                    case imem_if:read(ddTable, {schema(),TableName}) of
                        [] ->   imem_if:write(ddTable, DDTableRow); % ddTable meta data is missing
                        _ ->    ok
                    end,
                    throw(Reason)
            end,
            imem_cache:clear({?MODULE, trigger, schema(), TableName});
        _ ->
            try        
                % ?Info("creating table with opts ~p ~p ~n", [TableName,if_opts(Opts)]),
                imem_if:create_table(TableName, column_names(ColInfos), if_opts(Opts) ++ [{user_properties, [DDTableRow]}]),
                imem_if:write(ddTable, DDTableRow),
                imem_if:write(ddAlias, DDAliasRow)
            catch
                _:{'ClientError',{"Table already exists",TableName}} = Reason ->
                    case imem_if:read(ddTable, {schema(),TableName}) of
                        [] ->   imem_if:write(ddTable, DDTableRow); % ddTable meta data is missing
                        _ ->    ok
                    end,
                    case imem_if:read(ddAlias, {schema(),TableAlias}) of
                        [] ->   imem_if:write(ddAlias, DDAliasRow); % ddAlias meta data is missing
                        _ ->    ok
                    end,
                    throw(Reason)
            end,
            imem_cache:clear({?MODULE, trigger, schema(), TableAlias}),
            imem_cache:clear({?MODULE, trigger, schema(), TableName})
    end.

create_table_sys_conf(TableName, ColumnInfos, Opts, Owner) ->
    DDTableRow = #ddTable{qname={ddSysConf,TableName}, columns=ColumnInfos, opts=Opts, owner=Owner},
    return_atomic_ok(imem_if:write(ddTable, DDTableRow)).


create_trigger({Schema,Table},TFun) ->
    MySchema = schema(),
    case Schema of
        MySchema -> create_trigger(Table,TFun);
        _ ->        ?UnimplementedException({"Create Trigger in foreign schema",{Schema,Table}})
    end;
create_trigger(Table,TFunStr) when is_atom(Table) ->
    case read(ddTable,{schema(), Table}) of
        [#ddTable{}=D] -> 
            case lists:keysearch(trigger, 1, D#ddTable.opts) of
                false ->            create_or_replace_trigger(Table,TFunStr);
                {value,TFunStr} ->  ?ClientError({"Trigger already exists",{Table}});
                {value,Trig} ->     ?ClientError({"Trigger already exists",{Table,Trig}})
            end;
        [] ->
            ?ClientError({"Table dictionary does not exist for",Table})
    end.

create_or_replace_trigger({Schema,Table},TFun) ->
    MySchema = schema(),
    case Schema of
        MySchema -> create_or_replace_trigger(Table,TFun);
        _ ->        ?UnimplementedException({"Create Trigger in foreign schema",{Schema,Table}})
    end;
create_or_replace_trigger(Table,TFunStr) when is_atom(Table) ->
    % ?LogDebug("Create trigger ~p~n~p",[Table,TFunStr]),
    imem_datatype:io_to_fun(TFunStr,4),
    case read(ddTable,{schema(), Table}) of
        [#ddTable{}=D] -> 
            Opts = lists:keydelete(trigger, 1, D#ddTable.opts) ++ [{trigger,TFunStr}],
            Trans = fun() ->
                write(ddTable, D#ddTable{opts=Opts}),                       
                imem_cache:clear({?MODULE, trigger, schema(), Table})
            end,
            return_atomic_ok(transaction(Trans));
        [] ->
            ?ClientError({"Table dictionary does not exist for",Table})
    end;   
create_or_replace_trigger(Table,_) when is_atom(Table) ->
    ?ClientError({"Bad fun for create_or_replace_trigger, expecting arity 4", Table}).


create_index_table(IndexTable,ParentOpts,Owner) ->
    IndexOpts = case lists:keysearch(purge_delay, 1, ParentOpts) of
                false ->        ?DD_INDEX_OPTS;
                {value,PD} ->   ?DD_INDEX_OPTS ++ [{purge_delay,PD}]
    end,
    init_create_table(IndexTable, {record_info(fields, ddIndex), ?ddIndex, #ddIndex{}}, IndexOpts, Owner). 

create_index({Schema,Table},IndexDefinition) when is_list(IndexDefinition) ->
    MySchema = schema(),
    case Schema of
        MySchema -> create_index(Table,IndexDefinition);
        _ ->        ?UnimplementedException({"Create Index in foreign schema",{Schema,Table}})
    end;
create_index(Table,IndexDefinition) when is_atom(Table),is_list(IndexDefinition) ->
    case read(ddTable,{schema(), Table}) of
        [#ddTable{}=D] -> 
            case lists:keysearch(index, 1, D#ddTable.opts) of
                false ->                    create_or_replace_index(Table,IndexDefinition);
                {value,IndexDefinition} ->  ?ClientError({"Index already exists",{Table}});
                {value,IDL} ->              ?ClientError({"Index already exists",{Table,IDL}})
            end;
        [] ->
            ?ClientError({"Table dictionary does not exist for",Table})
    end.

create_or_replace_index({Schema,Table},IndexDefinition) when is_list(IndexDefinition) ->
    MySchema = schema(),
    case Schema of
        MySchema -> create_or_replace_index(Table,IndexDefinition);
        _ ->        ?UnimplementedException({"Create Index in foreign schema",{Schema,Table}})
    end;
create_or_replace_index(Table,IndexDefinition) when is_atom(Table),is_list(IndexDefinition) ->
    % ?LogDebug("Create index ~p~n~p",[Table,IndexDefinition]),
    case read(ddTable,{schema(), Table}) of
        [#ddTable{}=D] -> 
            Opts = lists:keydelete(index, 1, D#ddTable.opts) ++ [{index,IndexDefinition}],
            IndexTable = ?INDEX_TABLE(Table),
            case (catch check_table(IndexTable)) of
                ok ->   
                    Trans = fun() ->
                        lock({table, Table}, write),
                        write(ddTable, D#ddTable{opts=Opts}),                       
                        imem_cache:clear({?MODULE, trigger, schema(), Table}),
                        imem_if:truncate_table(IndexTable)
                        %% ToDo: fold through Table and insert index rows
                    end,
                    return_atomic_ok(transaction(Trans));
                _ ->
                    create_index_table(IndexTable,D#ddTable.opts,D#ddTable.owner),
                    Trans = fun() ->
                        lock({table, Table}, write),
                        write(ddTable, D#ddTable{opts=Opts}),                       
                        imem_cache:clear({?MODULE, trigger, schema(), Table})
                        %% ToDo: fold through Table and insert index rows
                    end,
                    return_atomic_ok(transaction(Trans))
            end;
        [] ->
            ?ClientError({"Table dictionary does not exist for",Table})
    end.

drop_index({Schema,Table}) ->
    MySchema = schema(),
    case Schema of
        MySchema -> drop_index(Table);
        _ ->        ?UnimplementedException({"Drop Index in foreign schema",{Schema,Table}})
    end;
drop_index(Table) when is_atom(Table) ->
    case read(ddTable,{schema(), Table}) of
        [#ddTable{}=D] -> 
            Opts = lists:keydelete(index, 1, D#ddTable.opts),
            Trans = fun() ->
                write(ddTable, D#ddTable{opts=Opts}),                       
                imem_cache:clear({?MODULE, trigger, schema(), Table})
            end,
            ok = return_atomic_ok(transaction(Trans)),
            catch drop_table(?INDEX_TABLE(Table));
        [] ->
            ?ClientError({"Table dictionary does not exist for",Table})
    end.


drop_trigger({Schema,Table}) ->
    MySchema = schema(),
    case Schema of
        MySchema -> drop_trigger(Table);
        _ ->        ?UnimplementedException({"Drop Trigger in foreign schema",{Schema,Table}})
    end;
drop_trigger(Table) when is_atom(Table) ->
    case read(ddTable,{schema(), Table}) of
        [#ddTable{}=D] -> 
            Opts = lists:keydelete(trigger, 1, D#ddTable.opts),
            Trans = fun() ->
                write(ddTable, D#ddTable{opts=Opts}),                       
                imem_cache:clear({?MODULE, trigger, schema(), Table})
            end,
            return_atomic_ok(transaction(Trans));
        [] ->
            ?ClientError({"Table dictionary does not exist for",Table})
    end.

is_valid_table_name(Table) when is_atom(Table) ->
    is_valid_table_name(atom_to_list(Table));
is_valid_table_name(Table) when is_list(Table) ->
    [H|_] = Table,
    L = lists:last(Table),
    if
        H == $" andalso L == $" -> true;
        true -> (length(Table) == length(Table -- ?BAD_NAME_CHARACTERS))
    end.

is_valid_column_name(Column) ->
    is_valid_table_name(atom_to_list(Column)).

if_opts(Opts) ->
    % Remove imem_meta table options which are not recognized by imem_if
    if_opts(Opts,?META_OPTS).

if_opts([],_) -> [];
if_opts(Opts,[]) -> Opts;
if_opts(Opts,[MO|Others]) ->
    if_opts(lists:keydelete(MO, 1, Opts),Others).

truncate_table(TableAlias) ->
    truncate_table(TableAlias,meta_field_value(user)).

truncate_table({Schema,TableAlias,_Alias},User) ->
    truncate_table({Schema,TableAlias},User);    
truncate_table({Schema,TableAlias},User) ->
    MySchema = schema(),
    case Schema of
        MySchema -> truncate_table(TableAlias, User);
        _ ->        ?UnimplementedException({"Truncate table in foreign schema",{Schema,TableAlias}})
    end;
truncate_table(TableAlias,User) when is_atom(TableAlias) ->
    %% log_to_db(debug,?MODULE,truncate_table,[{table,TableAlias}],"truncate table"),
    truncate_partitioned_tables(lists:sort(simple_or_local_node_sharded_tables(TableAlias)),User);
truncate_table(TableAlias, User) ->
    truncate_table(qualified_table_name(TableAlias),User).

truncate_partitioned_tables([],_) -> ok;
truncate_partitioned_tables([TableName|TableNames], User) ->
    {_, _, Trigger} =  trigger_infos(TableName),
    Trans = fun() ->
        Trigger({},{},TableName,User),
        imem_if:truncate_table(TableName)
    end,
    return_atomic_ok(transaction(Trans)),
    truncate_partitioned_tables(TableNames,User).

snapshot_table({_Schema,Table,_Alias}) ->
    snapshot_table({_Schema,Table});    
snapshot_table({Schema,Table}) ->
    MySchema = schema(),
    case Schema of
        MySchema -> snapshot_table(Table);
        _ ->        ?UnimplementedException({"Snapshot table in foreign schema",{Schema,Table}})
    end;
snapshot_table(Alias) when is_atom(Alias) ->
    log_to_db(debug,?MODULE,snapshot_table,[{table,Alias}],"snapshot table"),
    case lists:sort(simple_or_local_node_sharded_tables(Alias)) of
        [] ->   ?ClientError({"Table does not exist",Alias});
        PTNs -> case lists:usort([check_table(T) || T <- PTNs]) of
                    [ok] -> snapshot_partitioned_tables(PTNs);
                    _ ->    ?ClientError({"Table does not exist",Alias})
                end
    end;
snapshot_table(TableName) ->
    snapshot_table(qualified_table_name(TableName)).

snapshot_partitioned_tables([]) -> ok;
snapshot_partitioned_tables([TableName|TableNames]) ->
    imem_snap:take(TableName),
    snapshot_partitioned_tables(TableNames).

restore_table({_Schema,Table,_Alias}) ->
    restore_table({_Schema,Table});    
restore_table({Schema,Table}) ->
    MySchema = schema(),
    case Schema of
        MySchema -> restore_table(Table);
        _ ->        ?UnimplementedException({"Restore table in foreign schema",{Schema,Table}})
    end;
restore_table(Alias) when is_atom(Alias) ->
    log_to_db(debug,?MODULE,restore_table,[{table,Alias}],"restore table"),
    case lists:sort(simple_or_local_node_sharded_tables(Alias)) of
        [] ->   ?ClientError({"Table does not exist",Alias});
        PTNs -> case imem_snap:restore(bkp,PTNs,destroy,false) of
                    L when is_list(L) ->    ok;
                    E ->                    ?SystemException({"Restore table failed with",E})
                end
    end;    
restore_table(TableName) ->
    restore_table(qualified_table_name(TableName)).

drop_table({Schema,TableAlias}) when is_atom(Schema), is_atom(TableAlias) ->
    MySchema = schema(),
    case Schema of
        MySchema -> drop_table(TableAlias);
        _ ->        ?UnimplementedException({"Drop table in foreign schema",{Schema,TableAlias}})
    end;
drop_table(TableAlias) when is_atom(TableAlias) ->
    case is_system_table(TableAlias) of
        true -> ?ClientError({"Cannot drop system table",TableAlias});
        false-> drop_tables_and_infos(TableAlias,lists:sort(simple_or_local_node_sharded_tables(TableAlias)))
    end;
drop_table(TableAlias) when is_binary(TableAlias) ->
    drop_table(qualified_table_name(TableAlias)).

drop_system_table(TableAlias) when is_atom(TableAlias) ->
    case is_system_table(TableAlias) of
        false -> ?ClientError({"Not a system table",TableAlias});
        true ->  drop_tables_and_infos(TableAlias,lists:sort(simple_or_local_node_sharded_tables(TableAlias)))
    end.

drop_tables_and_infos(TableName,[TableName]) ->
    drop_table_and_info(TableName);
drop_tables_and_infos(TableAlias, []) -> 
     imem_if:delete(ddAlias, {schema(),TableAlias});
drop_tables_and_infos(TableAlias,[TableName|TableNames]) ->
    drop_table_and_info(TableName),
    drop_tables_and_infos(TableAlias,TableNames).

drop_table_and_info(TableName) ->
    try
        imem_if:drop_table(TableName),
        case TableName of
            ddTable ->  ok;
            ddAlias ->  ok;
            _ ->        imem_if:delete(ddTable, {schema(),TableName})
        end
    catch
        throw:{'ClientError',{"Table does not exist",Table}} ->
            catch imem_if:delete(ddTable, {schema(),TableName}),
            throw({'ClientError',{"Table does not exist",Table}})
    end.       

purge_table(TableAlias) ->
    purge_table(TableAlias, []).

purge_table({Schema,TableAlias,_Alias}, Opts) -> 
    purge_table({Schema,TableAlias}, Opts);
purge_table({Schema,TableAlias}, Opts) ->
    MySchema = schema(),
    case Schema of
        MySchema -> purge_table(TableAlias, Opts);
        _ ->        ?UnimplementedException({"Purge table in foreign schema",{Schema,TableAlias}})
    end;
purge_table(TableAlias, Opts) ->
    case is_time_partitioned_alias(TableAlias) of
        false ->    
            ?UnimplementedException({"Purge not supported on this table type",TableAlias});
        true ->
            purge_time_partitioned_table(TableAlias, Opts)
    end.

purge_time_partitioned_table(TableAlias, Opts) ->
    case lists:sort(simple_or_local_node_sharded_tables(TableAlias)) of
        [] ->
            ?ClientError({"Table to be purged does not exist",TableAlias});
        [TableName|_] ->
            KeepTime = case proplists:get_value(purge_delay, Opts) of
                undefined ->    erlang:now();
                Seconds ->      {Mega,Secs,Micro} = erlang:now(),
                                {Mega,Secs-Seconds,Micro}
            end,
            KeepName = partitioned_table_name(TableAlias,KeepTime),
            if  
                TableName >= KeepName ->
                    0;      %% no memory could be freed       
                true ->
                    FreedMemory = table_memory(TableName),
                    ?Info("Purge time partition ~p~n",[TableName]),
                    drop_table_and_info(TableName),
                    FreedMemory
            end
    end.

simple_or_local_node_sharded_tables(TableAlias) ->    
    case is_node_sharded_alias(TableAlias) of
        true ->
            case is_time_partitioned_alias(TableAlias) of
                true ->
                    Tail = lists:reverse("@" ++ node_shard()),
                    Pred = fun(TN) -> lists:prefix(Tail, lists:reverse(atom_to_list(TN))) end,
                    lists:filter(Pred,physical_table_names(TableAlias));
                false ->
                    [physical_table_name(TableAlias)]
            end;        
        false ->
            [physical_table_name(TableAlias)]
    end.

is_node_sharded_alias(TableAlias) when is_atom(TableAlias) -> 
    is_node_sharded_alias(atom_to_list(TableAlias));
is_node_sharded_alias(TableAlias) when is_list(TableAlias) -> (lists:last(TableAlias) == $@).

is_time_partitioned_alias(TableAlias) when is_atom(TableAlias) ->
    is_time_partitioned_alias(atom_to_list(TableAlias));
is_time_partitioned_alias(TableAlias) when is_list(TableAlias) ->
    case is_node_sharded_alias(TableAlias) of
        false -> 
            false;
        true ->
            case string:tokens(lists:reverse(TableAlias), "_") of
                [[$@|RN]|_] -> 
                    try 
                        _ = list_to_integer(lists:reverse(RN)),
                        true    % timestamp partitioned and node sharded alias
                    catch
                        _:_ -> false
                    end;
                 _ ->      
                    false       % node sharded alias only
            end
    end.

is_local_node_sharded_table(Name) when is_atom(Name) -> 
    is_local_node_sharded_table(atom_to_list(Name));
is_local_node_sharded_table(Name) when is_list(Name) -> 
    lists:suffix([$@|node_shard()],Name).

is_local_time_partitioned_table(Name) when is_atom(Name) ->
    is_local_time_partitioned_table(atom_to_list(Name));
is_local_time_partitioned_table(Name) when is_list(Name) ->
    case is_local_node_sharded_table(Name) of
        false -> 
            false;
        true ->
            is_time_partitioned_alias(lists:sublist(Name, length(Name)-length(node_shard())))
    end.

parse_table_name(TableName) when is_atom(TableName) -> 
    parse_table_name(atom_to_list(TableName));
parse_table_name(TableName) when is_list(TableName) ->
    %% TableName -> [Schema,".",Name,Period,"@",Node] all strings , all optional except Name
    case string:tokens(TableName, ".") of
        [R2] ->         ["",""|parse_simple_name(R2)];
        [Schema|R1] ->  [Schema,"."|parse_simple_name(string:join(R1,"."))]
    end.

parse_simple_name(TableName) when is_list(TableName) ->
    %% TableName -> [Name,Period,"@",Node] all strings , all optional except Name        
    case string:tokens(TableName, "@") of
        [BaseName] ->    
            [BaseName,"","",""];
        [Name,Node] ->
            case string:tokens(Name, "_") of  
                [Name] ->  
                    [Name,"","@",Node];
                BL ->     
                    case catch list_to_integer(lists:last(BL)) of
                        I when is_integer(I) ->
                            [string:join(lists:sublist(BL,length(BL)-1),"."),lists:last(BL),"@",Node];
                        _ ->
                            [Name,"","@",Node]
                    end
            end;
        _ ->
            [TableName,"","",""]
    end.

time_to_partition_expiry(Table) when is_atom(Table) ->
    time_to_partition_expiry(atom_to_list(Table));
time_to_partition_expiry(Table) when is_list(Table) ->
    case parse_table_name(Table) of
        [_Schema,_Dot,_BaseName,"",_Aterate,_Shard] ->
            ?ClientError({"Not a time partitioned table",Table});     
        [_Schema,_Dot,_BaseName,Number,_Aterate,_Shard] ->
            {Mega,Secs,_} = erlang:now(),
            list_to_integer(Number) - Mega * 1000000 - Secs
    end.

time_of_partition_expiry(Table) when is_atom(Table) ->
    time_of_partition_expiry(atom_to_list(Table));
time_of_partition_expiry(Table) when is_list(Table) ->
    case parse_table_name(Table) of
        [_Schema,_Dot,_BaseName,"",_Aterate,_Shard] ->
            ?ClientError({"Not a time partitioned table",Table});     
        [_Schema,_Dot,_BaseName,N,_Aterate,_Shard] ->
            Number = list_to_integer(N),
            {Number div 1000000, Number rem 1000000, 0}
    end.

% physical_table_name({_S,N,_A}) -> physical_table_name(N);
physical_table_name({_S,N}) -> physical_table_name(N);
physical_table_name(dba_tables) -> ddTable;
physical_table_name(all_tables) -> ddTable;
physical_table_name(all_aliases) -> ddAlias;
physical_table_name(user_tables) -> ddTable;
physical_table_name(TableAlias) when is_atom(TableAlias) ->
    case lists:member(TableAlias,?DataTypes) of
        true ->     TableAlias;
        false ->    physical_table_name(atom_to_list(TableAlias))
    end;
physical_table_name(TableAlias) when is_list(TableAlias) ->
    case lists:last(TableAlias) of
        $@ ->   partitioned_table_name(TableAlias,erlang:now());
        _ ->    list_to_atom(TableAlias)
    end.

% physical_table_name({_S,N,_A},Key) -> physical_table_name(N,Key);
physical_table_name({_S,N},Key) -> physical_table_name(N,Key);
physical_table_name(dba_tables,_) -> ddTable;
physical_table_name(all_tables,_) -> ddTable;
physical_table_name(all_aliases,_) -> ddAlias;
physical_table_name(user_tables,_) -> ddTable;
physical_table_name(TableAlias,Key) when is_atom(TableAlias) ->
    case lists:member(TableAlias,?DataTypes) of
        true ->     TableAlias;
        false ->    physical_table_name(atom_to_list(TableAlias),Key)
    end;
physical_table_name(TableAlias,Key) when is_list(TableAlias) ->
    case lists:last(TableAlias) of
        $@ ->
            partitioned_table_name(TableAlias,Key);
        _ ->    
            list_to_atom(TableAlias)
    end.

physical_table_names({_S,N,_A}) -> physical_table_names(N);
physical_table_names({_S,N}) -> physical_table_names(N);
physical_table_names(dba_tables) -> [ddTable];
physical_table_names(all_tables) -> [ddTable];
physical_table_names(all_aliases) -> [ddAlias];
physical_table_names(user_tables) -> [ddTable];
physical_table_names(TableAlias) when is_atom(TableAlias) ->
    case lists:member(TableAlias,?DataTypes) of
        true ->     [TableAlias];
        false ->    physical_table_names(atom_to_list(TableAlias))
    end;
physical_table_names(TableAlias) when is_list(TableAlias) ->
    case lists:last(TableAlias) of
        $@ ->   
            case string:tokens(lists:reverse(TableAlias), "_") of
                [[$@|RN]|_] ->
                    % timestamp sharded node sharded tables 
                    try 
                        _ = list_to_integer(lists:reverse(RN)),
                        {BaseName,_} = lists:split(length(TableAlias)-length(RN)-1, TableAlias),
                        Pred = fun(TN) -> lists:member($@, atom_to_list(TN)) end,
                        lists:filter(Pred,tables_starting_with(BaseName))
                    catch
                        _:_ -> tables_starting_with(TableAlias)
                    end;
                 _ ->   
                    % node sharded tables only   
                    tables_starting_with(TableAlias)
            end;
        _ ->    
            [list_to_atom(TableAlias)]
    end.

partitioned_table_name(TableAlias,Key) ->
    list_to_atom(partitioned_table_name_str(TableAlias,Key)).

partitioned_table_name_str(TableAlias,Key) when is_atom(TableAlias) ->
    partitioned_table_name_str(atom_to_list(TableAlias),Key);
partitioned_table_name_str(TableAlias,Key) when is_list(TableAlias) ->
    case string:tokens(lists:reverse(TableAlias), "_") of
        [[$@|RN]|_] ->
            % timestamp sharded node sharded table 
            try 
                Period = list_to_integer(lists:reverse(RN)),
                {Mega,Sec,_} = Key,
                PartitionEnd=integer_to_list(Period*((1000000*Mega+Sec) div Period) + Period),
                Prefix = lists:duplicate(10-length(PartitionEnd),$0),
                {BaseName,_} = lists:split(length(TableAlias)-length(RN)-1, TableAlias),
                lists:flatten(BaseName ++ Prefix ++ PartitionEnd ++ "@" ++ node_shard())
            catch
                _:_ -> lists:flatten(TableAlias ++ node_shard())
            end;
         _ ->
            % node sharded table only   
            lists:flatten(TableAlias ++ node_shard())
    end.

qualified_table_name({undefined,Table}) when is_atom(Table) ->              {schema(),Table};
qualified_table_name(Table) when is_atom(Table) ->                          {schema(),Table};
qualified_table_name({Schema,Table}) when is_atom(Schema),is_atom(Table) -> {Schema,Table};
qualified_table_name({undefined,T}) when is_binary(T) ->
    try
        {schema(),?binary_to_existing_atom(T)}
    catch
        _:_ -> ?ClientError({"Unknown Table name",T})
    end;
qualified_table_name({S,T}) when is_binary(S),is_binary(T) ->
    try
        {?binary_to_existing_atom(S),?binary_to_existing_atom(T)}
    catch
        _:_ -> ?ClientError({"Unknown Schema or Table name",{S,T}})
    end;
qualified_table_name(Table) when is_binary(Table) ->                        
    qualified_table_name(imem_sql_expr:binstr_to_qname2(Table)).

qualified_new_table_name({undefined,Table}) when is_atom(Table) ->              {schema(),Table};
qualified_new_table_name({undefined,Table}) when is_binary(Table) ->            {schema(),?binary_to_atom(Table)};
qualified_new_table_name({Schema,Table}) when is_atom(Schema),is_atom(Table) -> {Schema,Table};
qualified_new_table_name({S,T}) when is_binary(S),is_binary(T) ->               {?binary_to_atom(S),?binary_to_atom(T)};
qualified_new_table_name(Table) when is_atom(Table) ->                          {schema(),Table};
qualified_new_table_name(Table) when is_binary(Table) ->
    qualified_new_table_name(imem_sql_expr:binstr_to_qname2(Table)).

tables_starting_with(Prefix) when is_atom(Prefix) ->
    tables_starting_with(atom_to_list(Prefix));
tables_starting_with(Prefix) when is_list(Prefix) ->
    atoms_starting_with(Prefix,all_tables()).

atoms_starting_with(Prefix,Atoms) ->
    atoms_starting_with(Prefix,Atoms,[]). 

atoms_starting_with(_,[],Acc) -> lists:sort(Acc);
atoms_starting_with(Prefix,[A|Atoms],Acc) ->
    case lists:prefix(Prefix,atom_to_list(A)) of
        true ->     atoms_starting_with(Prefix,Atoms,[A|Acc]);
        false ->    atoms_starting_with(Prefix,Atoms,Acc)
    end.

tables_ending_with(Suffix) when is_atom(Suffix) ->
    tables_ending_with(atom_to_list(Suffix));
tables_ending_with(Suffix) when is_list(Suffix) ->
    atoms_ending_with(Suffix,all_tables()).

atoms_ending_with(Suffix,Atoms) ->
    atoms_ending_with(Suffix,Atoms,[]).

atoms_ending_with(_,[],Acc) -> lists:sort(Acc);
atoms_ending_with(Suffix,[A|Atoms],Acc) ->
    case lists:suffix(Suffix,atom_to_list(A)) of
        true ->     atoms_ending_with(Suffix,Atoms,[A|Acc]);
        false ->    atoms_ending_with(Suffix,Atoms,Acc)
    end.


%% one to one from imme_if -------------- HELPER FUNCTIONS ------


compile_fun(Binary) when is_binary(Binary) ->
    compile_fun(binary_to_list(Binary)); 
compile_fun(String) when is_list(String) ->
    try  
        Code = case [lists:last(string:strip(String))] of
            "." -> String;
            _ -> String ++ "."
        end,
        {ok,ErlTokens,_}=erl_scan:string(Code),    
        {ok,ErlAbsForm}=erl_parse:parse_exprs(ErlTokens),    
        {value,Fun,_}=erl_eval:exprs(ErlAbsForm,[]),    
        Fun
    catch
        _:Reason ->
            ?Error("Compiling script function ~p results in ~p",[String,Reason]), 
            undefined
    end.

schema() ->
    imem_if:schema().

schema(Node) ->
    imem_if:schema(Node).

system_id() ->
    imem_if:system_id().

add_attribute(A, Opts) -> 
    imem_if:add_attribute(A, Opts).

update_opts(T, Opts) ->
    imem_if:update_opts(T, Opts).

failing_function([]) -> 
    {undefined,undefined, 0};
failing_function([{imem_meta,throw_exception,_,_}|STrace]) -> 
    failing_function(STrace);
failing_function([{M,N,_,FileInfo}|STrace]) ->
    case lists:prefix("imem",atom_to_list(M)) of
        true ->
            NAsBin = atom_to_binary(N, utf8),
            Line = proplists:get_value(line, FileInfo, 0),
            case re:run(NAsBin, <<"-(.+)/">>, [{capture, all_but_first, binary}]) of
                nomatch ->
                    {M, N, Line};
                {match, [FunNameBin]} ->
                    {M, binary_to_atom(FunNameBin, utf8), Line}
            end;
        false ->
            failing_function(STrace)
    end;
failing_function(_Other) ->
    ?Debug("unexpected stack trace ~p~n", [_Other]),
    {undefined,undefined, 0}.

log_to_db(Level,Module,Function,Fields,Message)  ->
    log_to_db(Level,Module,Function,Fields,Message,[]).

log_to_db(Level,Module,Function,Fields,Message,Stacktrace) ->
    BinStr = try 
        list_to_binary(Message)
    catch
        _:_ ->  list_to_binary(lists:flatten(io_lib:format("~tp",[Message])))
    end,
    log_to_db(Level,Module,Function,0,Fields,BinStr,Stacktrace).

log_to_db(Level,Module,Function,Line,Fields,Message,StackTrace)
when is_atom(Level)
    , is_atom(Module)
    , is_atom(Function)
    , is_integer(Line)
    , is_list(Fields)
    , is_binary(Message)
    , is_list(StackTrace) ->
    LogRec = #ddLog{logTime=erlang:now(),logLevel=Level,pid=self()
                    ,module=Module,function=Function,line=Line,node=node()
                    ,fields=Fields,message=Message,stacktrace=StackTrace
                    },
    dirty_write(?LOG_TABLE, LogRec).


log_slow_process(Module,Function,STT,LimitWarning,LimitError,Fields) ->
    DurationMs = imem_datatype:msec_diff(STT),
    if 
        DurationMs < LimitWarning ->    ok;
        DurationMs < LimitError ->      log_to_db(warning,Module,Function,Fields,"slow_process",[]);
        true ->                         log_to_db(error,Module,Function,Fields,"slow_process",[])
    end.

%% imem_if but security context added --- META INFORMATION ------

data_nodes() ->
    imem_if:data_nodes().

all_tables() ->
    imem_if:all_tables().

all_aliases() ->
    MySchema = schema(),
    [A || #ddAlias{qname={S,A}} <- imem_if:read(ddAlias),S==MySchema].

is_readable_table({_Schema,Table}) ->
    is_readable_table(Table);   %% ToDo: may depend on schema
is_readable_table(Table) ->
    imem_if:is_readable_table(Table).

is_virtual_table({_Schema,Table}) ->
    is_virtual_table(Table);   %% ToDo: may depend on schema
is_virtual_table(Table) ->
    lists:member(Table,?VirtualTables).

node_shard() ->
    case application:get_env(imem, node_shard) of
        {ok,NS} when is_list(NS) ->      NS;
        {ok,NI} when is_integer(NI) ->   integer_to_list(NI);
        undefined ->                     node_hash(node());    
        {ok,node_shard_fun} ->  
            try 
                node_shard_value(application:get_env(imem, node_shard_fun),node())
            catch
                _:_ ->  ?Debug("bad config parameter ~p~n", [node_shard_fun]),
                        "nohost"
            end;
        {ok,host_name} ->                host_name(node());    
        {ok,host_fqdn} ->                host_fqdn(node());    
        {ok,node_name} ->                node_name(node());    
        {ok,node_hash} ->                node_hash(node());    
        {ok,NA} when is_atom(NA) ->      atom_to_list(NA);
        _Else ->    ?Debug("bad config parameter ~p ~p~n", [node_shard, _Else]),
                    node_hash(node())
    end.

node_shard_value({ok,FunStr},Node) ->
    % ?Debug("node_shard calculated for ~p~n", [FunStr]),
    Code = case [lists:last(string:strip(FunStr))] of
        "." -> FunStr;
        _ -> FunStr ++ "."
    end,
    {ok,ErlTokens,_}=erl_scan:string(Code),    
    {ok,ErlAbsForm}=erl_parse:parse_exprs(ErlTokens),    
    {value,Value,_}=erl_eval:exprs(ErlAbsForm,[]),    
    Result = Value(Node),
    % ?Debug("node_shard_value ~p~n", [Result]),
    Result.

host_fqdn(Node) when is_atom(Node) -> 
    NodeStr = atom_to_list(Node),
    [_,Fqdn] = string:tokens(NodeStr, "@"),
    Fqdn.

host_name(Node) when is_atom(Node) -> 
    [Host|_] = string:tokens(host_fqdn(Node), "."),
    Host.

node_name(Node) when is_atom(Node) -> 
    NodeStr = atom_to_list(Node),
    [Name,_] = string:tokens(NodeStr, "@"),
    Name.

node_hash(Node) when is_atom(Node) ->
    io_lib:format("~6.6.0w",[erlang:phash2(Node, 1000000)]).

trigger_infos(Table) when is_atom(Table) ->
    trigger_infos({schema(),Table});
trigger_infos({Schema,Table}) when is_atom(Schema),is_atom(Table) ->
    Key = {?MODULE,trigger,Schema,Table},
    case imem_cache:read(Key) of 
        [] ->
            case imem_if:read(ddTable,{Schema, Table}) of
                [] ->
                    ?ClientError({"Table does not exist",{Schema, Table}}); 
                [#ddTable{columns=ColumnInfos,opts=Opts}] ->
                    TableType = case lists:keyfind(type,1,Opts) of
                        false ->    set;
                        {_,Type} -> Type
                    end,
                    RecordName = case lists:keyfind(record_name,1,Opts) of
                        false ->    Table;
                        {_,Name} -> Name
                    end,
                    DefRec = [RecordName|column_info_items(ColumnInfos, default_fun)],
                    IdxDef = case lists:keyfind(index,1,Opts) of
                        false ->    [];
                        {_,Def} ->  Def
                    end,
                    Trigger = case {IdxDef,lists:keyfind(trigger,1,Opts)} of
                        {[],false} ->   fun(_Old,_New,_Tab,_User) -> ok end;
                        {_,false} ->    fun(Old,New,Tab,User) -> imem_meta:update_index(Old,New,Tab,User,IdxDef) end;
                        {_,{_,TFun}} -> 
                            TriggerWithIndexing = trigger_with_indexing(TFun,<<"imem_meta:update_index">>,<<"IdxDef">>),
                            imem_datatype:io_to_fun(TriggerWithIndexing,undefined,[{'IdxDef',IdxDef}])
                    end,
                    Result = {TableType, DefRec, Trigger},
                    imem_cache:write(Key,Result),
                    % ?LogDebug("trigger_infos ~p",[Result]),
                    Result
            end;
        [{TT, DR, TR}] ->
            {TT, DR, TR}
    end.

trigger_with_indexing(TFun,MF,Var) ->
    case re:run(TFun, "fun\\((.*)\\)[ ]*\->(.*)end.", [global, {capture, [1,2], binary}]) of
        {match,[[Params,Body0]]} ->
            case binary:match(Body0,MF) of
                nomatch ->    <<"fun(",Params/binary,") ->",Body0/binary,", ",MF/binary,"(",Params/binary,",",Var/binary,") end." >>;
                {_,_} ->     TFun
            end
    end.

table_type({ddSysConf,Table}) ->
    imem_if_sys_conf:table_type(Table);
table_type({_Schema,Table}) ->
    table_type(Table);          %% ToDo: may depend on schema
table_type(Table) when is_atom(Table) ->
    imem_if:table_type(physical_table_name(Table)).

table_record_name({ddSysConf,Table}) ->
    imem_if_sys_conf:table_record_name(Table);   %% ToDo: may depend on schema
table_record_name({_Schema,Table}) ->
    table_record_name(Table);   %% ToDo: may depend on schema
table_record_name(ddNode)  -> ddNode;
table_record_name(ddSchema)  -> ddSchema;
table_record_name(ddSize)  -> ddSize;
table_record_name(Table) when is_atom(Table) ->
    imem_if:table_record_name(physical_table_name(Table)).

table_columns({ddSysConf,Table}) ->
    imem_if_sys_conf:table_columns(Table);
table_columns({_Schema,Table}) ->
    table_columns(Table);       %% ToDo: may depend on schema
table_columns(Table) ->
    imem_if:table_columns(physical_table_name(Table)).

table_size({ddSysConf,_Table}) ->
    %% imem_if_sys_conf:table_size(Table);
    0;                                                  %% ToDo: implement there
table_size({_Schema,Table}) ->  table_size(Table);      %% ToDo: may depend on schema
table_size(ddNode) ->           length(read(ddNode));
table_size(ddSchema) ->         length(read(ddSchema));
table_size(ddSize) ->           1;
table_size(Table) ->
    %% ToDo: sum should be returned for all local time partitions
    imem_if:table_size(physical_table_name(Table)).

table_memory({ddSysConf,_Table}) ->
    %% imem_if_sys_conf:table_memory(Table);
    0;                                                  %% ToDo: implement there                    
table_memory({_Schema,Table}) ->
    table_memory(Table);                                %% ToDo: may depend on schema
table_memory(Table) ->
    %% ToDo: sum should be returned for all local time partitions
    imem_if:table_memory(physical_table_name(Table)).

exec(Statement, BlockSize, Schema) ->
    imem_sql:exec(none, Statement, BlockSize, Schema, false).   

fetch_recs(Pid, Sock, Timeout) ->
    imem_statement:fetch_recs(none, Pid, Sock, Timeout, false).

fetch_recs_sort(Pid, Sock, Timeout) ->
    imem_statement:fetch_recs_sort(none, Pid, Sock, Timeout, false).

fetch_recs_async(Pid, Sock) ->
    imem_statement:fetch_recs_async(none, Pid, Sock, false).

fetch_recs_async(Opts, Pid, Sock) ->
    imem_statement:fetch_recs_async(none, Pid, Sock, Opts, false).

filter_and_sort(Pid, FilterSpec, SortSpec) ->
    imem_statement:filter_and_sort(none, Pid, FilterSpec, SortSpec, false).

filter_and_sort(Pid, FilterSpec, SortSpec, Cols) ->
    imem_statement:filter_and_sort(none, Pid, FilterSpec, SortSpec, Cols, false).

fetch_close(Pid) ->
    imem_statement:fetch_close(none, Pid, false).

update_prepare(Tables, ColMap, ChangeList) ->
    imem_statement:update_prepare(false, none, Tables, ColMap, ChangeList).

update_cursor_prepare(Pid, ChangeList) ->
    imem_statement:update_cursor_prepare(none, Pid, false, ChangeList).

update_cursor_execute(Pid, Lock) ->
    imem_statement:update_cursor_execute(none, Pid, false, Lock).

apply_defaults(DefRec, Rec) when is_tuple(DefRec) ->
    apply_defaults(tuple_to_list(DefRec), Rec);
apply_defaults(DefRec, Rec) when is_list(DefRec), is_tuple(Rec) ->
    apply_defaults(DefRec, Rec, 1).

apply_defaults([], Rec, _) -> Rec;
apply_defaults([D|DefRec], Rec0, N) ->
    Rec1 = case {element(N,Rec0),is_function(D),is_function(D,0)} of
        {?nav,true,true} ->     setelement(N,Rec0,D());
        {?nav,false,false} ->   setelement(N,Rec0,D);
        _ ->                    Rec0
    end,
    apply_defaults(DefRec, Rec1, N+1).

apply_validators(DefRec, Rec, Table) ->
    apply_validators(DefRec, Rec, Table, meta_field_value(user)).

apply_validators(DefRec, Rec, Table, User) when is_tuple(DefRec) ->
    apply_validators(tuple_to_list(DefRec), Rec, Table, User);
apply_validators(DefRec, Rec, Table, User) when is_list(DefRec), is_tuple(Rec) ->
    apply_validators(DefRec, Rec, Table, User, 1).

apply_validators([], Rec, _, _, _) -> Rec;
apply_validators([D|DefRec], Rec0, Table, User, N) ->
    Rec1 = if 
        is_function(D,1) -> setelement(N,Rec0,D(element(N,Rec0)));  %% Params=[Field]
        is_function(D,2) -> setelement(N,Rec0,D(element(N,Rec0),Rec0));  %% Params=[Field,Rec]
        is_function(D,3) -> setelement(N,Rec0,D(element(N,Rec0),Rec0,Table));  %% Params=[Field,Rec,Table]
        is_function(D,4) -> setelement(N,Rec0,D(element(N,Rec0),Rec0,Table,User));  %% Params=[Field,Rec,Table,User]
        true ->             Rec0
    end,
    apply_validators(DefRec, Rec1, Table, User, N+1).

fetch_start(Pid, {ddSysConf,Table}, MatchSpec, BlockSize, Opts) ->
    imem_if_sys_conf:fetch_start(Pid, Table, MatchSpec, BlockSize, Opts);
fetch_start(Pid, {_Schema,Table}, MatchSpec, BlockSize, Opts) ->
    fetch_start(Pid, Table, MatchSpec, BlockSize, Opts);          %% ToDo: may depend on schema
fetch_start(Pid, ddNode, MatchSpec, BlockSize, Opts) ->
    fetch_start_virtual(Pid, ddNode, MatchSpec, BlockSize, Opts);
fetch_start(Pid, ddSchema, MatchSpec, BlockSize, Opts) ->
    fetch_start_virtual(Pid, ddSchema, MatchSpec, BlockSize, Opts);
fetch_start(Pid, ddSize, MatchSpec, BlockSize, Opts) ->
    fetch_start_virtual(Pid, ddSize, MatchSpec, BlockSize, Opts);
fetch_start(Pid, Table, MatchSpec, BlockSize, Opts) ->
    imem_if:fetch_start(Pid, physical_table_name(Table), MatchSpec, BlockSize, Opts).

fetch_start_virtual(Pid, VTable, MatchSpec, _BlockSize, _Opts) ->
    % ?Debug("Virtual fetch start  : ~p ~p~n", [VTable,MatchSpec]),
    {Rows,true} = select(VTable, MatchSpec),
    % ?Debug("Virtual fetch result  : ~p~n", [Rows]),
    spawn(
        fun() ->
            receive
                abort ->    ok;
                next ->     Pid ! {row, [?sot,?eot|Rows]}
            end
        end
    ).

close(Pid) ->
    imem_statement:close(none, Pid).

read({ddSysConf,_Table}) -> 
    % imem_if_sys_conf:read(physical_table_name(Table));
    ?UnimplementedException({"Cannot read from ddSysConf schema, use DDerl GUI instead"});
read({_Schema,Table}) -> 
    read(Table);            %% ToDo: may depend on schema
read(ddNode) ->
    lists:flatten([read(ddNode,Node) || Node <- [node()|nodes()]]);
read(ddSchema) ->
    [{ddSchema,{Schema,Node},[]} || {Schema,Node} <- data_nodes()];
read(ddSize) ->
    [hd(read(ddSize,Name)) || Name <- all_tables()];
read(Table) ->
    imem_if:read(physical_table_name(Table)).

read({ddSysConf,Table}, _Key) -> 
    % imem_if_sys_conf:read(physical_table_name(Table),Key);
    ?UnimplementedException({"Cannot read from ddSysConf schema, use DDerl GUI instead",Table});
read({_Schema,Table}, Key) ->
    read(Table, Key);
read(ddNode,Node) when is_atom(Node) ->
    case rpc:call(Node,erlang,statistics,[wall_clock],?DDNODE_TIMEOUT) of
        {WC,WCDiff} when is_integer(WC), is_integer(WCDiff) ->
            case rpc:call(Node,erlang,now,[],?DDNODE_TIMEOUT) of
                {Meg,Sec,Mic} when is_integer(Meg),is_integer(Sec),is_integer(Mic) ->                        
                    [#ddNode{ name=Node
                             , wall_clock=WC
                             , time={Meg,Sec,Mic}
                             , extra=[]     
                             }       
                    ];
                _ ->    
                    []
            end;
         _ -> 
            []
    end;
read(ddNode,_) -> [];
read(ddSchema,Key) when is_tuple(Key) ->
    [ S || #ddSchema{schemaNode=K} = S <- read(ddSchema), K==Key];
read(ddSchema,_) -> [];
read(ddSize,Table) ->
    PTN =  physical_table_name(Table),
    case is_local_time_partitioned_table(PTN) of  % 
        true ->
            case (catch {table_size(PTN),table_memory(PTN), time_of_partition_expiry(PTN),time_to_partition_expiry(PTN)}) of
                {S,M,E,T} when is_integer(S),is_integer(M) -> 
                    [{ddSize,PTN,S,M,E,T}];
                _ ->                    
                    [{ddSize,PTN,undefined,undefined,undefined,undefined}]
            end;
        false ->
            case (catch {table_size(PTN),table_memory(PTN)}) of
                {S,M} when is_integer(S),is_integer(M) -> 
                    [{ddSize,PTN,S,M,undefined,undefined}];
                _ ->                    
                    [{ddSize,PTN,undefined,undefined,undefined,undefined}]
            end
    end;            
read(Table, Key) -> 
    imem_if:read(physical_table_name(Table), Key).

dirty_read({ddSysConf,Table}, Key) -> read({ddSysConf,Table}, Key);
dirty_read({_Schema,Table}, Key) ->   dirty_read(Table, Key);
dirty_read(ddNode,Node) ->  read(ddNode,Node); 
dirty_read(ddSchema,Key) -> read(ddSchema,Key);
dirty_read(ddSize,Table) -> read(ddSize,Table);
dirty_read(Table, Key) ->   imem_if:dirty_read(physical_table_name(Table), Key).


read_hlk({_Schema,Table}, HListKey) -> 
    read_hlk(Table, HListKey);
read_hlk(Table,HListKey) ->
    imem_if:read_hlk(Table,HListKey).

get_config_hlk({_Schema,Table}, Key, Owner, Context, Default) ->
    get_config_hlk(Table, Key, Owner, Context, Default);
get_config_hlk(Table, Key, Owner, Context, Default) when is_atom(Table), is_list(Context), is_atom(Owner) ->
    Remark = list_to_binary(["auto_provisioned from ",io_lib:format("~p",[Context])]),
    case (catch read_hlk(Table, [Key|Context])) of
        [] ->                                   
            %% no value found, create global config with default value
            catch put_config_hlk(Table, Key, Owner, [], Default, Remark),
            Default;
        [#ddConfig{val=Default, hkl=[Key]}] ->    
            %% global config is relevant and matches default
            Default;
        [#ddConfig{val=OldVal, hkl=[Key], remark=R, owner=DefOwner}] ->
            %% global config is relevant and differs from default
            case binary:longest_common_prefix([R,<<"auto_provisioned">>]) of
                16 ->
                    %% comment starts with default comment may be overwrite
                    case {DefOwner, Owner} of
                        _ when
                                  ((?MODULE     =:= DefOwner)
                            orelse (Owner       =:= DefOwner)                            
                            orelse (undefined   =:= DefOwner)) ->
                            %% was created by imem_meta and/or same module
                            %% overwrite the default
                            catch put_config_hlk(Table, Key, Owner, [], Default, Remark),
                            Default;
                        _ ->
                            %% being accessed by non creator, protect creator's config value
                            OldVal
                    end;
                _ ->    
                    %% comment was changed by user, protect his config value
                    OldVal
            end;
        [#ddConfig{val=Val}] ->
            %% config value is overridden by user, return that value
            Val;
        _ ->
            %% fallback in case ddConf is deleted in a running system
            Default
    end.

put_config_hlk({_Schema,Table}, Key, Owner, Context, Value, Remark) ->
    put_config_hlk(Table, Key, Owner, Context, Value, Remark);
put_config_hlk(Table, Key, Owner, Context, Value, Remark) when is_atom(Table), is_list(Context), is_binary(Remark) ->
    write(Table,#ddConfig{hkl=[Key|Context], val=Value, remark=Remark, owner=Owner}).

select({ddSysConf,Table}, _MatchSpec) ->
    % imem_if_sys_conf:select(physical_table_name(Table), MatchSpec);
    ?UnimplementedException({"Cannot select from ddSysConf schema, use DDerl GUI instead",Table});
select({_Schema,Table}, MatchSpec) ->
    select(Table, MatchSpec);           %% ToDo: may depend on schema
select(ddNode, MatchSpec) ->
    select_virtual(ddNode, MatchSpec);
select(ddSchema, MatchSpec) ->
    select_virtual(ddSchema, MatchSpec);
select(ddSize, MatchSpec) ->
    select_virtual(ddSize, MatchSpec);
select(Table, MatchSpec) ->
    imem_if:select(physical_table_name(Table), MatchSpec).

select(Table, MatchSpec, 0) ->
    select(Table, MatchSpec);
select({ddSysConf,Table}, _MatchSpec, _Limit) ->
    % imem_if_sys_conf:select(physical_table_name(Table), MatchSpec, Limit);
    ?UnimplementedException({"Cannot select from ddSysConf schema, use DDerl GUI instead",Table});
select({_Schema,Table}, MatchSpec, Limit) ->
    select(Table, MatchSpec, Limit);        %% ToDo: may depend on schema
select(ddNode, MatchSpec, _Limit) ->
    select_virtual(ddNode, MatchSpec);
select(ddSchema, MatchSpec, _Limit) ->
    select_virtual(ddSchema, MatchSpec);
select(ddSize, MatchSpec, _Limit) ->
    select_virtual(ddSize, MatchSpec);
select(Table, MatchSpec, Limit) ->
    imem_if:select(physical_table_name(Table), MatchSpec, Limit).

select_virtual(_Table, [{_,[false],['$_']}]) ->
    {[],true};
select_virtual(Table, [{_,[true],['$_']}]) ->
    {read(Table),true};                 %% used in select * from virtual_table
select_virtual(Table, [{_,[],['$_']}]) ->
    {read(Table),true};                 %% used in select * from virtual_table
select_virtual(Table, [{MatchHead, [Guard], ['$_']}]=MatchSpec) ->
    Tag = element(2,MatchHead),
    % ?Debug("Virtual Select Tag / MatchSpec: ~p / ~p~n", [Tag,MatchSpec]),
    Candidates = case operand_match(Tag,Guard) of
        false ->                        read(Table);
        {'==',Tag,{element,N,Tup1}} ->  % ?Debug("Virtual Select Key : ~p~n", [element(N,Tup1)]),
                                        read(Table,element(N,Tup1));
        {'==',{element,N,Tup2},Tag} ->  % ?Debug("Virtual Select Key : ~p~n", [element(N,Tup2)]),
                                        read(Table,element(N,Tup2));
        {'==',Tag,Val1} ->              % ?Debug("Virtual Select Key : ~p~n", [Val1]),
                                        read(Table,Val1);
        {'==',Val2,Tag} ->              % ?Debug("Virtual Select Key : ~p~n", [Val2]),
                                        read(Table,Val2);
        _ ->                            read(Table)
    end,
    % ?Debug("Virtual Select Candidates  : ~p~n", [Candidates]),
    MS = ets:match_spec_compile(MatchSpec),
    Result = ets:match_spec_run(Candidates,MS),
    % ?Debug("Virtual Select Result  : ~p~n", [Result]),    
    {Result, true}.

%% Does this guard use the operand Tx?      TODO: Generalize from guard tree to expression tree
operand_match(Tx,{_,Tx}=C0) ->      C0;
operand_match(Tx,{_,R}) ->          operand_match(Tx,R);
operand_match(Tx,{_,Tx,_}=C1) ->    C1;
operand_match(Tx,{_,_,Tx}=C2) ->    C2;
operand_match(Tx,{_,L,R}) ->        case operand_match(Tx,L) of
                                        false ->    operand_match(Tx,R);
                                        Else ->     Else
                                    end;    
operand_match(Tx,Tx) ->             Tx;
operand_match(_,_) ->               false.

select_sort(Table, MatchSpec)->
    {L, true} = select(Table, MatchSpec),
    {lists:sort(L), true}.

select_sort(Table, MatchSpec, Limit) ->
    {Result, AllRead} = select(Table, MatchSpec, Limit),
    {lists:sort(Result), AllRead}.

write_log(Record) -> write(?LOG_TABLE, Record).

write({ddSysConf,TableAlias}, _Record) -> 
    % imem_if_sys_conf:write(TableAlias, Record);
    ?UnimplementedException({"Cannot write to ddSysConf schema, use DDerl GUI instead",TableAlias});
write({_Schema,TableAlias}, Record) ->
    write(TableAlias, Record);           %% ToDo: may depend on schema 
write(TableAlias, Record) ->
    % log_to_db(debug,?MODULE,write,[{table,TableAlias},{rec,Record}],"write"), 
    PTN = physical_table_name(TableAlias,element(?KeyIdx,Record)),
    try
        imem_if:write(PTN, Record)
    catch
        throw:{'ClientError',{"Table does not exist",T}} ->
            % ToDo: instruct imem_meta gen_server to create the table
            case is_time_partitioned_alias(TableAlias) of
                true ->
                    case create_partitioned_table_sync(TableAlias,PTN) of
                        ok ->   
                            imem_if:write(PTN, Record);
                        {error,recursive_call} ->
                            ok; %% cannot create a new partition now, skip logging to database
                        E ->
                            ?ClientError({"Table partition cannot be created",{PTN,E}})
                    end;        
                false ->
                    ?ClientError({"Table does not exist",T})
            end;
        _Class:Reason ->
            ?Debug("Write error ~p:~p~n", [_Class,Reason]),
            throw(Reason)
    end. 

dirty_write({ddSysConf,TableAlias}, _Record) -> 
    % imem_if_sys_conf:dirty_write(TableAlias, Record);
    ?UnimplementedException({"Cannot write to ddSysConf schema, use DDerl GUI instead",TableAlias});
dirty_write({_Schema,TableAlias}, Record) -> 
    dirty_write(TableAlias, Record);           %% ToDo: may depend on schema 
dirty_write(TableAlias, Record) -> 
    % log_to_db(debug,?MODULE,dirty_write,[{table,TableAlias},{rec,Record}],"dirty_write"), 
    PTN = physical_table_name(TableAlias,element(?KeyIdx,Record)),
    try
        imem_if:dirty_write(PTN, Record)
    catch
        throw:{'ClientError',{"Table does not exist",T}} ->
            case is_time_partitioned_alias(TableAlias) of
                true ->
                    case create_partitioned_table_sync(TableAlias,PTN) of
                        ok ->   
                            imem_if:dirty_write(PTN, Record);
                        {error,recursive_call} ->
                            ok; %% cannot create a new partition now, skip logging to database
                        E ->
                            ?ClientError({"Table partition cannot be created",{PTN,E}})
                    end;        
                false ->
                    ?ClientError({"Table does not exist",T})
            end;
        _Class:Reason ->
            ?Debug("Dirty write error ~p:~p~n", [_Class,Reason]),
            throw(Reason)
    end. 

insert(TableAlias, Row) ->
    insert(TableAlias,Row,meta_field_value(user)).

insert({ddSysConf,TableAlias}, _Row, _User) ->
    % imem_if_sys_conf:write(TableAlias, Row);     %% mapped to unconditional write
    ?UnimplementedException({"Cannot write to ddSysConf schema, use DDerl GUI instead",TableAlias});
insert({_Schema,TableAlias}, Row, User) ->
    insert(TableAlias, Row, User);               %% ToDo: may depend on schema
insert(TableAlias, Row, User) when is_atom(TableAlias), is_tuple(Row) ->
    {TableType, DefRec, Trigger} =  trigger_infos(TableAlias),
    modify(insert, TableType, TableAlias, DefRec, Trigger, Row, User).

update(TableAlias, Row) ->
    update(TableAlias, Row, meta_field_value(user)).

update({ddSysConf,TableAlias}, _Row, _User) ->
    % imem_if_sys_conf:write(TableAlias, Row);     %% mapped to unconditional write
    ?UnimplementedException({"Cannot write to ddSysConf schema, use DDerl GUI instead",TableAlias});    
update({_Schema,TableAlias}, Row, User) ->
    update(TableAlias, Row, User);               %% ToDo: may depend on schema
update(TableAlias, Row, User) when is_atom(TableAlias), is_tuple(Row) ->
    {TableType, DefRec, Trigger} =  trigger_infos(TableAlias),
    modify(update, TableType, TableAlias, DefRec, Trigger, Row, User).

merge(TableAlias, Row) ->
    merge(TableAlias, Row, meta_field_value(user)).

merge({ddSysConf,TableAlias}, _Row, _User) ->
    % imem_if_sys_conf:write(TableAlias, Row);     %% mapped to unconditional write
    ?UnimplementedException({"Cannot write to ddSysConf schema, use DDerl GUI instead",TableAlias});    
merge({_Schema,TableAlias}, Row, User) ->
    merge(TableAlias, Row, User);                %% ToDo: may depend on schema
merge(TableAlias, Row, User) when is_atom(TableAlias), is_tuple(Row) ->
    {TableType, DefRec, Trigger} =  trigger_infos(TableAlias),
    modify(merge, TableType, TableAlias, DefRec, Trigger, Row, User).

remove(TableAlias, Row) ->
    remove(TableAlias, Row, meta_field_value(user)).

remove({ddSysConf,TableAlias}, _Row, _User) ->
    % imem_if_sys_conf:delete(TableAlias, Row);    %% mapped to unconditional delete
    ?UnimplementedException({"Cannot delete from ddSysConf schema, use DDerl GUI instead",TableAlias});
remove({_Schema,TableAlias}, Row, User) ->
    remove(TableAlias, Row, User);               %% ToDo: may depend on schema
remove(TableAlias, Row, User) when is_atom(TableAlias), is_tuple(Row) ->
    {TableType, DefRec, Trigger} =  trigger_infos(TableAlias),
    modify(remove, TableType, TableAlias, DefRec, Trigger, Row, User).

modify(Operation, TableType, TableAlias, DefRec, Trigger, Row0, User) when is_atom(TableAlias), is_tuple(Row0) ->
    Row1=apply_defaults(DefRec, Row0),
    Row2=apply_validators(DefRec, Row1, TableAlias, User),
    Key = element(?KeyIdx,Row2),
    case ((TableAlias /= ddTable) and lists:member(?nav,tuple_to_list(Row2))) of
        false ->
            PTN = physical_table_name(TableAlias,Key),
            Trans = fun() ->   
                case {Operation, TableType, read(PTN,Key)} of     %% TODO: Wrap in single transaction
                    {insert,bag,Bag} -> case lists:member(Row2,Bag) of  
                                            true ->     ?ConcurrencyException({"Insert failed, object already exists", {PTN,Row2}});
                                            false ->    write(PTN, Row2),
                                                        Trigger({},Row2,PTN,User),
                                                        Row2
                                        end;
                    {insert,_,[]} ->    write(PTN, Row2),
                                        Trigger({},Row2,TableAlias,User),
                                        Row2;
                    {insert,_,[R]} ->   ?ConcurrencyException({"Insert failed, key already exists in", {PTN,R}});
                    {update,bag,_} ->   ?UnimplementedException({"Update is not supported on bag tables, use delete and insert", TableAlias});
                    {update,_,[]} ->    ?ConcurrencyException({"Update failed, key does not exist", {PTN,Key}});
                    {update,_,[R]} ->   write(PTN, Row2),
                                        Trigger(R,Row2,TableAlias,User),
                                        Row2;
                    {merge,bag,_} ->    ?UnimplementedException({"Merge is not supported on bag tables, use delete and insert", TableAlias});
                    {merge,_,[]} ->     write(PTN, Row2),
                                        Trigger({},Row2,TableAlias,User),
                                        Row2;
                    {merge,_,[R]} ->    write(PTN, Row2),
                                        Trigger(R,Row2,TableAlias,User),
                                        Row2;
                    {remove,bag,[]} ->  ?ConcurrencyException({"Remove failed, object does not exist", {PTN,Row2}});
                    {remove,_,[]} ->    ?ConcurrencyException({"Remove failed, key does not exist", {PTN,Key}});
                    {remove,bag,Bag} -> case lists:member(Row2,Bag) of  
                                            false ->    ?ConcurrencyException({"Remove failed, object does not exist", {PTN,Row2}});
                                            true ->     delete_object(PTN, Row2),
                                                        Trigger(Row2,{},PTN,User),
                                                        Row2
                                        end;
                    {remove,_,[R]} ->   delete(TableAlias, Key),
                                        Trigger(R,{},TableAlias,User),
                                        R
                end
            end,
            return_atomic(transaction(Trans));
        true ->     
            ?ClientError({"Not null constraint violation", {TableAlias,Row2}})
    end.


delete({_Schema,TableAlias}, Key) ->
    delete(TableAlias, Key);             %% ToDo: may depend on schema
delete(TableAlias, Key) ->
    imem_if:delete(physical_table_name(TableAlias,Key), Key).

delete_object({_Schema,TableAlias}, Row) ->
    delete_object(TableAlias, Row);             %% ToDo: may depend on schema
delete_object(TableAlias, Row) ->
    imem_if:delete_object(physical_table_name(TableAlias,element(?KeyIdx,Row)), Row).

subscribe({table, Tab, Mode}) ->
    PTN = physical_table_name(Tab),
    log_to_db(debug,?MODULE,subscribe,[{ec,{table, PTN, Mode}}],"subscribe to mnesia"),
    imem_if:subscribe({table, PTN, Mode});
subscribe(EventCategory) ->
    log_to_db(debug,?MODULE,subscribe,[{ec,EventCategory}],"subscribe to mnesia"),
    imem_if:subscribe(EventCategory).

unsubscribe({table, Tab, Mode}) ->
    PTN = physical_table_name(Tab),
    Result = imem_if:unsubscribe({table, PTN, Mode}),
    log_to_db(debug,?MODULE,unsubscribe,[{ec,{table, PTN, Mode}}],"unsubscribe from mnesia"),
    Result;
unsubscribe(EventCategory) ->
    Result = imem_if:unsubscribe(EventCategory),
    log_to_db(debug,?MODULE,unsubscribe,[{ec,EventCategory}],"unsubscribe from mnesia"),
    Result.

update_tables([[{Schema,_,_}|_]|_] = UpdatePlan, Lock) ->
    update_tables(Schema, UpdatePlan, Lock, []).

update_bound_counter(TableAlias, Field, Key, Incr, LimitMin, LimitMax) ->
    imem_if:update_bound_counter(physical_table_name(TableAlias), Field, Key, Incr, LimitMin, LimitMax).

update_tables(ddSysConf, [], Lock, Acc) ->
    imem_if_sys_conf:update_tables(Acc, Lock);  
update_tables(_MySchema, [], Lock, Acc) ->
    imem_if:update_tables(Acc, Lock);  
update_tables(MySchema, [UEntry|UPlan], Lock, Acc) ->
    % log_to_db(debug,?MODULE,update_tables,[{lock,Lock}],io_lib:format("~p",[UEntry])),
    update_tables(MySchema, UPlan, Lock, [update_table_name(MySchema, UEntry)|Acc]).

update_table_name(MySchema,[{MySchema,Tab,Type}, Item, Old, New, Trig, User]) ->
    case lists:member(?nav,tuple_to_list(New)) of
        false ->    [{physical_table_name(Tab),Type}, Item, Old, New, Trig, User];
        true ->     ?ClientError({"Not null constraint violation", {Item, {Tab,New}}})
    end.

update_index(_,_,_,_,[]) -> ok;
update_index(Old,New,Table,User,IdxDef) -> 
    update_index(Old,New,Table,User,IdxDef,[],[]). 

update_index(_Old,_New,_Table,_User,[],_Removes,_Inserts) ->
    %% ToDo: implement execution of Removes and Inserts
    ?LogDebug("update index table/rem/ins ~p~n~p~n~p",[_Table,_Removes,_Inserts]);
update_index(Old,New,Table,User,[_IdxDef|Defs],Removes,Inserts) ->
    %% ToDo: implement calculation of Removes and Inserts
    update_index(Old,New,Table,User,Defs,Removes,Inserts).

transaction(Function) ->
    imem_if:transaction(Function).

transaction(Function, Args) ->
    imem_if:transaction(Function, Args).

transaction(Function, Args, Retries) ->
    imem_if:transaction(Function, Args, Retries).

return_atomic_list(Result) ->
    imem_if:return_atomic_list(Result). 

return_atomic_ok(Result) -> 
    imem_if:return_atomic_ok(Result).

return_atomic(Result) -> 
    imem_if:return_atomic(Result).

foldl(FoldFun, InputAcc, Table) ->  
    imem_if:foldl(FoldFun, InputAcc, Table).

lock(LockItem, LockKind) -> 
    imem_if:lock(LockItem, LockKind).


%% ----- DATA TYPES ---------------------------------------------


%% ----- TESTS ------------------------------------------------
-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    ?imem_test_setup().

teardown(_) ->
    catch drop_table(meta_table_3),
    catch drop_table(meta_table_2),
    catch drop_table(meta_table_1),
    catch drop_table(tpTest_1000@),
    catch drop_table(test_config),
    catch drop_table(fakelog_1@),
    ?imem_test_teardown().

db_test_() ->
    {
        setup,
        fun setup/0,
        fun teardown/1,
        {with, [
              fun meta_operations/1
        ]}}.    

meta_operations(_) ->
    try 
        ClEr = 'ClientError',
        SyEx = 'SystemException', 
        UiEx = 'UnimplementedException', 

        ?Info("---TEST---~p:test_mnesia~n", [?MODULE]),

        ?Info("schema ~p~n", [imem_meta:schema()]),
        ?Info("data nodes ~p~n", [imem_meta:data_nodes()]),
        ?assertEqual(true, is_atom(imem_meta:schema())),
        ?assertEqual(true, lists:member({imem_meta:schema(),node()}, imem_meta:data_nodes())),

        ?assertEqual(ok, check_table_columns(ddTable, record_info(fields, ddTable))),

        ?assertEqual(ok, create_check_table(?LOG_TABLE, {record_info(fields, ddLog),?ddLog, #ddLog{}}, ?LOG_TABLE_OPTS, system)),
        ?assertException(throw,{SyEx,{"Wrong table owner",{?LOG_TABLE,system}}} ,create_check_table(?LOG_TABLE, {record_info(fields, ddLog),?ddLog, #ddLog{}}, [{record_name,ddLog},{type,ordered_set}], admin)),
        ?assertException(throw,{SyEx,{"Wrong table options",{?LOG_TABLE,_}}} ,create_check_table(?LOG_TABLE, {record_info(fields, ddLog),?ddLog, #ddLog{}}, [{record_name,ddLog1},{type,ordered_set}], system)),
        ?assertEqual(ok, check_table(?LOG_TABLE)),

        ?assertEqual(ok, check_table(?CACHE_TABLE)),

        Now = erlang:now(),
        LogCount1 = table_size(?LOG_TABLE),
        ?Info("ddLog@ count ~p~n", [LogCount1]),
        Fields=[{test_criterium_1,value1},{test_criterium_2,value2}],
        LogRec1 = #ddLog{logTime=Now,logLevel=info,pid=self()
                            ,module=?MODULE,function=meta_operations,node=node()
                            ,fields=Fields,message= <<"some log message 1">>},
        ?assertEqual(ok, write(?LOG_TABLE, LogRec1)),
        LogCount2 = table_size(?LOG_TABLE),
        ?Info("ddLog@ count ~p~n", [LogCount2]),
        ?assert(LogCount2 > LogCount1),
        Log1=read(?LOG_TABLE,Now),
        ?Info("ddLog@ content ~p~n", [Log1]),
        ?assertEqual(ok, log_to_db(info,?MODULE,test,[{test_3,value3},{test_4,value4}],"Message")),        
        ?assertEqual(ok, log_to_db(info,?MODULE,test,[{test_3,value3},{test_4,value4}],[])),        
        ?assertEqual(ok, log_to_db(info,?MODULE,test,[{test_3,value3},{test_4,value4}],[stupid_error_message,1])),        
        ?assertEqual(ok, log_to_db(info,?MODULE,test,[{test_3,value3},{test_4,value4}],{stupid_error_message,2})),        
        LogCount2a = table_size(?LOG_TABLE),
        ?assert(LogCount2a >= LogCount2+4),

        ?Info("~p:test_database_operations~n", [?MODULE]),
        Types1 =    [ #ddColumn{name=a, type=string, len=10}     %% key
                    , #ddColumn{name=b1, type=string, len=20}    %% value 1
                    , #ddColumn{name=c1, type=string, len=30}    %% value 2
                    ],
        Types2 =    [ #ddColumn{name=a, type=integer, len=10}    %% key
                    , #ddColumn{name=b2, type=float, len=8, prec=3}   %% value
                    ],

        BadTypes0 = [ #ddColumn{name='a', type=integer, len=10}  
                    ],
        BadTypes1 = [ #ddColumn{name='a', type=integer, len=10}
                    , #ddColumn{name='a:b', type=integer, len=10}  
                    ],
        BadTypes2 = [ #ddColumn{name='a', type=integer, len=10}
                    , #ddColumn{name=current, type=integer, len=10}
                    ],
        BadTypes3 = [ #ddColumn{name='a', type=integer, len=10}
                    , #ddColumn{name=a, type=iinteger, len=10}
                    ],

        ?assertEqual(ok, create_table(meta_table_1, Types1, [])),
        Idx1Def = #ddIdxDef{id=1,name= <<"string index on b1">>,pos=3,type=ivk,pl=[<<"">>]},
        ?assertEqual(ok, create_index(meta_table_1, [Idx1Def])),
        ?assertEqual(ok, check_table(idx_meta_table_1)),
        ?Info("ddTable  for meta_table_1~n~p~n", [read(ddTable,{schema(),meta_table_1})]),
        ?assertEqual(ok, drop_index(meta_table_1)),
        ?assertException(throw, {'ClientError',{"Table does not exist",idx_meta_table_1}}, check_table(idx_meta_table_1)),
        ?assertEqual(ok, create_index(meta_table_1, [])),
        ?assertException(throw, {'ClientError',{"Index already exists",{meta_table_1,{index,[]}}}}, create_index(meta_table_1, [])),
        ?assertEqual([], read(idx_meta_table_1)),
        ?assertEqual(ok, write(idx_meta_table_1, #ddIndex{stu={1,2,3}})),
        ?assertEqual([#ddIndex{stu={1,2,3}}], read(idx_meta_table_1)),
        ?assertEqual(ok, create_or_replace_index(meta_table_1, [])),
        ?assertEqual([], read(idx_meta_table_1)),

        ?assertEqual(ok, create_table(meta_table_2, Types2, [])),

        ?assertEqual(ok, create_table(meta_table_3, {[a,?nav],[datetime,term],{meta_table_3,?nav,undefined}}, [])),
        ?Info("success ~p~n", [create_table_not_null]),
        Trig = <<"fun(O,N,T,U) -> imem_meta:log_to_db(debug,imem_meta,trigger,[{table,T},{old,O},{new,N},{user,U}],\"trigger\") end.">>,
        ?assertEqual(ok, create_or_replace_trigger(meta_table_3, Trig)),

        ?assertException(throw, {ClEr,{"No columns given in create table",bad_table_0}}, create_table('bad_table_0', [], [])),
        ?assertException(throw, {ClEr,{"No value column given in create table, add dummy value column",bad_table_0}}, create_table('bad_table_0', BadTypes0, [])),

        ?assertException(throw, {ClEr,{"Invalid character(s) in table name", 'bad_?table_1'}}, create_table('bad_?table_1', BadTypes1, [])),
        ?assertException(throw, {ClEr,{"Reserved table name", select}}, create_table(select, BadTypes2, [])),

        ?assertException(throw, {ClEr,{"Invalid character(s) in column name", 'a:b'}}, create_table(bad_table_1, BadTypes1, [])),
        ?assertException(throw, {ClEr,{"Reserved column name", current}}, create_table(bad_table_1, BadTypes2, [])),
        ?assertException(throw, {ClEr,{"Invalid data type", iinteger}}, create_table(bad_table_1, BadTypes3, [])),

        LogCount3 = table_size(?LOG_TABLE),
        ?assertEqual({meta_table_3,{{2000,1,1},{12,45,55}},undefined}, insert(meta_table_3, {meta_table_3,{{2000,01,01},{12,45,55}},?nav})),
        ?assertEqual(1, table_size(meta_table_3)),
        ?assertEqual(LogCount3+1, table_size(?LOG_TABLE)),  %% trigger inserted one line      
        ?assertException(throw, {ClEr,{"Not null constraint violation", {meta_table_3,_}}}, insert(meta_table_3, {meta_table_3,?nav,undefined})),
        ?assertEqual(LogCount3+2, table_size(?LOG_TABLE)),  %% error inserted one line
        ?Info("success ~p~n", [not_null_constraint]),
        ?assertEqual({meta_table_3,{{2000,1,1},{12,45,55}},undefined}, update(meta_table_3, {meta_table_3,{{2000,01,01},{12,45,55}},?nav})),
        ?assertEqual(1, table_size(meta_table_3)),
        ?assertEqual(LogCount3+3, table_size(?LOG_TABLE)),  %% trigger inserted one line 
        ?assertEqual({meta_table_3,{{2000,1,1},{12,45,56}},undefined}, merge(meta_table_3, {meta_table_3,{{2000,01,01},{12,45,56}},?nav})),
        ?assertEqual(2, table_size(meta_table_3)),
        ?assertEqual(LogCount3+4, table_size(?LOG_TABLE)),  %% trigger inserted one line 
        ?assertEqual({meta_table_3,{{2000,1,1},{12,45,56}},undefined}, remove(meta_table_3, {meta_table_3,{{2000,01,01},{12,45,56}},?nav})),
        ?assertEqual(1, table_size(meta_table_3)),
        ?assertEqual(LogCount3+5, table_size(?LOG_TABLE)),  %% trigger inserted one line 
        ?assertEqual(ok, drop_trigger(meta_table_3)),
        Trans3 = fun() ->
            update(meta_table_3, {meta_table_3,{{2000,01,01},{12,45,55}},?nav}),
            insert(meta_table_3, {meta_table_3,{{2000,01,01},{12,45,57}},?nav})
        end,
        ?assertEqual({meta_table_3,{{2000,1,1},{12,45,57}},undefined}, return_atomic(transaction(Trans3))),
        ?assertEqual(2, table_size(meta_table_3)),
        ?assertEqual(LogCount3+5, table_size(?LOG_TABLE)),  %% no trigger, no more log  

        Keys4 = [
        {1,{meta_table_3,{{2000,1,1},{12,45,59}},undefined}}
        ],
        U = unknown,
        {TT4,_DefRec,TrigFun} = trigger_infos(meta_table_3),
        ?assertEqual(Keys4, update_tables([[{imem,meta_table_3,set}, 1, {}, {meta_table_3,{{2000,01,01},{12,45,59}},undefined},TrigFun,U]], optimistic)),
        ?assertException(throw, {ClEr,{"Not null constraint violation", {1,{meta_table_3,_}}}}, update_tables([[{imem,meta_table_3,set}, 1, {}, {meta_table_3, ?nav, undefined},TrigFun,U]], optimistic)),
        ?assertException(throw, {ClEr,{"Not null constraint violation", {1,{meta_table_3,_}}}}, update_tables([[{imem,meta_table_3,set}, 1, {}, {meta_table_3,{{2000,01,01},{12,45,59}}, ?nav},TrigFun,U]], optimistic)),
        
        LogTable = physical_table_name(?LOG_TABLE),
        ?assert(lists:member(LogTable,physical_table_names(?LOG_TABLE))),

        ?assertEqual([],physical_table_names(tpTest_1000@)),

        ?assertException(throw, {ClEr,{"Table to be purged does not exist",tpTest_1000@}}, purge_table(tpTest_1000@)),
        ?assertException(throw, {UiEx,{"Purge not supported on this table type",not_existing_table}}, purge_table(not_existing_table)),
        ?assert(purge_table(?LOG_TABLE) >= 0),
        ?assertException(throw, {UiEx,{"Purge not supported on this table type",ddTable}}, purge_table(ddTable)),

        TimePartTable0 = physical_table_name(tpTest_1000@),
        ?Info("TimePartTable ~p~n", [TimePartTable0]),
        ?assertEqual(TimePartTable0, physical_table_name(tpTest_1000@,erlang:now())),
        ?assertEqual(ok, create_check_table(tpTest_1000@, {record_info(fields, ddLog),?ddLog, #ddLog{}}, [{record_name,ddLog},{type,ordered_set}], system)),
        ?assertEqual(ok, check_table(TimePartTable0)),
        ?assertEqual(0, table_size(TimePartTable0)),

        Alias0 = read(ddAlias),
        % ?Info("Alias0 ~p~n", [Alias0]),
        ?assert(lists:member({schema(),tpTest_1000@},[element(2,A) || A <- Alias0])),

        ?assertEqual(ok, write(tpTest_1000@, LogRec1)),
        ?assertEqual(1, table_size(TimePartTable0)),
        ?assertEqual(0, purge_table(tpTest_1000@)),
        {Megs,Secs,Mics} = erlang:now(),
        FutureSecs = Megs*1000000 + Secs + 2000,
        Future = {FutureSecs div 1000000,FutureSecs rem 1000000,Mics}, 
        LogRec2 = #ddLog{logTime=Future,logLevel=info,pid=self()
                            ,module=?MODULE,function=meta_operations,node=node()
                            ,fields=Fields,message= <<"some log message 2">>},
        ?assertEqual(ok, write(tpTest_1000@, LogRec2)),
        ?Info("physical_table_names ~p~n", [physical_table_names(tpTest_1000@)]),
        ?assertEqual(0, purge_table(tpTest_1000@,[{purge_delay,10000}])),
        ?assertEqual(0, purge_table(tpTest_1000@)),
        PurgeResult = purge_table(tpTest_1000@,[{purge_delay,-3000}]),
        ?Info("PurgeResult ~p~n", [PurgeResult]),
        ?assert(PurgeResult>0),
        ?assertEqual(0, purge_table(tpTest_1000@)),
        ?assertEqual(ok, drop_table(tpTest_1000@)),
        ?assertEqual([],physical_table_names(tpTest_1000@)),
        Alias1 = read(ddAlias),
        % ?Info("Alias1 ~p~n", [Alias1]),
        ?assertEqual(false,lists:member({schema(),tpTest_1000@},[element(2,A) || A <- Alias1])),
        ?Info("success ~p~n", [tpTest_1000@]),

        ?assertEqual([meta_table_1,meta_table_2,meta_table_3],lists:sort(tables_starting_with("meta_table_"))),
        ?assertEqual([meta_table_1,meta_table_2,meta_table_3],lists:sort(tables_starting_with(meta_table_))),

        DdNode0 = read(ddNode),
        ?Info("ddNode0 ~p~n", [DdNode0]),
        DdNode1 = read(ddNode,node()),
        ?Info("ddNode1 ~p~n", [DdNode1]),
        DdNode2 = select(ddNode,?MatchAllRecords),
        ?Info("ddNode2 ~p~n", [DdNode2]),

        Schema0 = [{ddSchema,{schema(),node()},[]}],
        ?assertEqual(Schema0, read(ddSchema)),
        ?assertEqual({Schema0,true}, select(ddSchema,?MatchAllRecords)),

        ?assertEqual(ok, create_table(test_config, {record_info(fields, ddConfig),?ddConfig, #ddConfig{}}, ?CONFIG_TABLE_OPTS, system)),
        ?assertEqual(test_value,get_config_hlk(test_config, {?MODULE,test_param}, test_owner, [test_context], test_value)),
        ?assertMatch([#ddConfig{hkl=[{?MODULE,test_param}],val=test_value}],read(test_config)), %% default created, owner set
        ?assertEqual(test_value,get_config_hlk(test_config, {?MODULE,test_param}, not_test_owner, [test_context], other_default)),
        ?assertMatch([#ddConfig{hkl=[{?MODULE,test_param}],val=test_value}],read(test_config)), %% default not overwritten, wrong owner
        ?assertEqual(test_value1,get_config_hlk(test_config, {?MODULE,test_param}, test_owner, [test_context], test_value1)),
        ?assertMatch([#ddConfig{hkl=[{?MODULE,test_param}],val=test_value1}],read(test_config)), %% new default overwritten by owner
        ?assertEqual(ok, put_config_hlk(test_config, {?MODULE,test_param}, test_owner, [],test_value2,<<"Test Remark">>)),
        ?assertEqual(test_value2,get_config_hlk(test_config, {?MODULE,test_param}, test_owner, [test_context], test_value3)),
        ?assertMatch([#ddConfig{hkl=[{?MODULE,test_param}],val=test_value2}],read(test_config)),
        ?assertEqual(ok, put_config_hlk(test_config, {?MODULE,test_param}, test_owner, [test_context],context_value,<<"Test Remark">>)),
        ?assertEqual(context_value,get_config_hlk(test_config, {?MODULE,test_param}, test_owner, [test_context], test_value)),
        ?assertEqual(context_value,get_config_hlk(test_config, {?MODULE,test_param}, test_owner, [test_context,details], test_value)),
        ?assertEqual(test_value2,get_config_hlk(test_config, {?MODULE,test_param}, test_owner, [another_context,details], another_value)),
        ?Info("success ~p~n", [get_config_hlk]),

        ?assertEqual( {error,{"Table template not found in ddAlias",dummy_table_name}}, create_partitioned_table_sync(dummy_table_name,dummy_table_name)),
        ?assertEqual([],physical_table_names(fakelog_1@)),
        ?assertEqual(ok, create_check_table(fakelog_1@, {record_info(fields, ddLog),?ddLog, #ddLog{}}, ?LOG_TABLE_OPTS, system)),    
        ?assertEqual(1,length(physical_table_names(fakelog_1@))),
        LogRec3 = #ddLog{logTime=erlang:now(),logLevel=debug,pid=self()
                        ,module=?MODULE,function=test,node=node()
                        ,fields=[],message= <<>>,stacktrace=[]
                    },
        ?assertEqual(ok, dirty_write(fakelog_1@, LogRec3)),
        timer:sleep(1000),
        ?assertEqual(ok, dirty_write(fakelog_1@, LogRec3#ddLog{logTime=erlang:now()})),
        ?assert(length(physical_table_names(fakelog_1@)) >= 3),
        timer:sleep(1100),
        % ?assertEqual(ok, create_partitioned_table_sync(fakelog_1@,physical_table_name(fakelog_1@))),
        ?assert(length(physical_table_names(fakelog_1@)) >= 4),
        ?Info("success ~p~n", [create_partitioned_table]),

        ?assertEqual(ok, drop_table(meta_table_3)),
        ?assertEqual(ok, drop_table(meta_table_2)),
        ?assertEqual(ok, drop_table(meta_table_1)),
        ?assertEqual(ok, drop_table(test_config)),
        ?assertEqual(ok,drop_table(fakelog_1@)),

        ?Info("success ~p~n", [drop_tables])
    catch
        Class:Reason ->     
            timer:sleep(1000),
            ?Info("Exception ~p:~p~n~p~n", [Class, Reason, erlang:get_stacktrace()]),
            throw ({Class, Reason})
    end,
    ok.
    
-endif.
