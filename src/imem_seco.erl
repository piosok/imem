-module(imem_seco).

-define(PASSWORD_VALIDITY,100).

-include("imem_seco.hrl").

-behavior(gen_server).

-record(state, {
        }).

-export([ start_link/1
        ]).

% gen_server interface (monitoring calling processes)
-export([ monitor/1
        , cleanup_pid/1
        ]).

% gen_server behavior callbacks
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        , format_status/2
        ]).

% security context library interface
-export([ drop_seco_tables/1
        , create_credentials/1
        , create_credentials/2
        ]).

-export([ authenticate/3
        , login/1
        , change_credentials/3
        , logout/1
        ]).

-export([ has_role/3
        , has_permission/3
%%        , my_quota/2
        ]).

-export([ have_role/2
        , have_permission/2
        ]).

%       returns a ref() of the monitor
monitor(Pid) when is_pid(Pid) -> gen_server:call(?MODULE, {monitor, Pid}).

start_link(Params) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Params, []).

init(_Args) ->
    io:format(user, "~p starting...~n", [?MODULE]),
    Result = try %% try creating system tables, may fail if they exist, then check existence 
        if_table_size(none, ddTable),
        catch if_create_table(none, ddAccount, record_info(fields, ddAccount),[], system),
        if_table_size(none, ddAccount),
        catch if_create_table(none, ddRole, record_info(fields, ddRole),[], system),          
        if_table_size(none, ddRole),
        catch if_create_table(none, ddSeCo, record_info(fields, ddSeCo),[local, {local_content,true}], system),     
        if_table_size(none, ddSeCo),
        catch if_create_table(none, ddPerm, record_info(fields, ddPerm),[local, {local_content,true}], system),     
        if_table_size(none, ddPerm),
        catch if_create_table(none, ddQuota, record_info(fields, ddQuota),[local, {local_content,true}], system),     
        if_table_size(none, ddQuota),
        UserName= <<"admin">>,
        case if_select_account_by_name(none, UserName) of
            {[],true} ->  
                    UserId = make_ref(),
                    UserCred=create_credentials(pwdmd5, <<"change_on_install">>),
                    User = #ddAccount{id=UserId, name=UserName, credentials=[UserCred]
                                        ,fullName= <<"DB Administrator">>, lastPasswordChangeTime=calendar:local_time()},
                    if_write(none, ddAccount, User),                    
                    if_write(none, ddRole, #ddRole{id=UserId,roles=[],permissions=[manage_accounts, manage_system_tables, manage_user_tables]});
            _ ->    ok       
        end,        
        io:format(user, "~p started!~n", [?MODULE]),
        {ok,#state{}}    
    catch
        Class:Reason -> io:format(user, "~p failed with ~p:~p~n", [?MODULE,Class,Reason]),
                        {stop, "Insufficient resources for start"} 
    end,
    Result.

handle_call({monitor, Pid}, _From, State) ->
    io:format(user, "~p - started monitoring pid ~p~n", [?MODULE, Pid]),
    {reply, erlang:monitor(process, Pid), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({'DOWN', Ref, process, Pid, Reason}, State) ->
    io:format(user, "~p - received exit for monitored pid ~p ref ~p reason ~p~n", [?MODULE, Pid, Ref, Reason]),
    cleanup_pid(Pid),
    {noreply, State};
% handle_cast({stop, Reason}, State) ->
%     {stop,{shutdown,Reason},State};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reson, _State) -> ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, [_PDict, _State]) -> ok.


%% --Interface functions  (duplicated in dd_account) ----------------------------------

if_select(_SKey, Table, MatchSpec) ->
    imem_meta:select(Table, MatchSpec). 

if_select_seco_keys_by_pid(SKey, Pid) -> 
    MatchHead = #ddSeCo{skey='$1', pid='$2', _='_'},
    Guard = {'==', '$2', Pid},
    Result = '$1',
    if_select(SKey, ddSeCo, [{MatchHead, [Guard], [Result]}]).

if_select_perm_keys_by_skey(_SKeyM, SKey) ->      %% M=Monitor / MasterContext 
    MatchHead = #ddPerm{pkey='$1', skey='$2', _='_'},
    Guard = {'==', '$2', SKey},
    Result = '$1',
    if_select(SKey, ddPerm, [{MatchHead, [Guard], [Result]}]).

if_select_account_by_name(SKey, Name) -> 
    MatchHead = #ddAccount{name='$1', _='_'},
    Guard = {'==', '$1', Name},
    Result = '$_',
    if_select(SKey, ddAccount, [{MatchHead, [Guard], [Result]}]).

if_table_size(_SeKey, Table) ->
    imem_meta:table_size(Table).

%% --Interface functions  (calling imem_meta) ----------------------------------

if_create_table(_SKey, Table, RecordInfo, Opts, Owner) ->
    imem_meta:create_table(Table, RecordInfo, Opts, Owner).


if_drop_table(_SKey, Table) -> 
    imem_meta:drop_table(Table).

if_write(_SKey, Table, Record) -> 
    imem_meta:write(Table, Record).

if_read(_SKey, Table, Key) -> 
    imem_meta:read(Table, Key).

if_delete(_SKey, Table, RowId) ->
    imem_meta:delete(Table, RowId).

if_has_role(_SKey, _RootRoleId, _RootRoleId) ->
    true;
if_has_role(SKey, RootRoleId, RoleId) ->
    case if_read(SKey, ddRole, RootRoleId) of
        [#ddRole{roles=[]}] ->          false;
        [#ddRole{roles=ChildRoles}] ->  if_has_child_role(SKey,  ChildRoles, RoleId);
        [] ->                           %% ToDo: log missing role
                                        false
    end.

if_has_child_role(_SKey, [], _RoleId) -> false;
if_has_child_role(SKey, [RootRoleId|OtherRoles], RoleId) ->
    case if_has_role(SKey, RootRoleId, RoleId) of
        true ->                         true;
        false ->                        if_has_child_role(SKey, OtherRoles, RoleId)
    end.

if_has_permission(_SKey, _RootRoleId, []) ->
    false;
if_has_permission(SKey, RootRoleId, PermissionList) when is_list(PermissionList)->
    %% search for first match in list of permissions
    case if_read(SKey, ddRole, RootRoleId) of
        [#ddRole{permissions=[],roles=[]}] ->     
            false;
        [#ddRole{permissions=Permissions, roles=[]}] -> 
            list_member(PermissionList, Permissions);
        [#ddRole{permissions=Permissions, roles=ChildRoles}] ->
            case list_member(PermissionList, Permissions) of
                true ->     true;
                false ->    if_has_child_permission(SKey,  ChildRoles, PermissionList)
            end;
        [] ->
            %% ToDo: log missing role
            false
    end;
if_has_permission(SKey, RootRoleId, PermissionId) ->
    %% search for single permission
    case if_read(SKey, ddRole, RootRoleId) of
        [#ddRole{permissions=[],roles=[]}] ->     
            false;
        [#ddRole{permissions=Permissions, roles=[]}] -> 
            lists:member(PermissionId, Permissions);
        [#ddRole{permissions=Permissions, roles=ChildRoles}] ->
            case lists:member(PermissionId, Permissions) of
                true ->     true;
                false ->    if_has_child_permission(SKey,  ChildRoles, PermissionId)
            end;
        [] ->
             %% ToDo: log missing role
            false
    end.

if_has_child_permission(_SKey, [], _Permission) -> false;
if_has_child_permission(SKey, [RootRoleId|OtherRoles], Permission) ->
    case if_has_permission(SKey, RootRoleId, Permission) of
        true ->     true;
        false ->    if_has_child_permission(SKey, OtherRoles, Permission)
    end.


%% --Implementation (exported helper functions) ----------------------------------------

create_credentials(Password) ->
    create_credentials(pwdmd5, Password).

create_credentials(Type, Password) when is_list(Password) ->
    create_credentials(Type, list_to_binary(Password));
create_credentials(Type, Password) when is_integer(Password) ->
    create_credentials(Type, list_to_binary(integer_to_list(Password)));
create_credentials(pwdmd5, Password) ->
    {pwdmd5, erlang:md5(Password)}.


cleanup_pid(Pid) ->
    MonitorPid =  whereis(?MODULE),
    case self() of
        MonitorPid ->    
            {SKeys,true} = if_select_seco_keys_by_pid(none,Pid),
            seco_delete(none, SKeys);
        _ ->
            ?SecurityViolation({"Cleanup unauthorized",{self(),Pid}})
    end.

list_member([], _Permissions) ->
    false;
list_member([PermissionId|Rest], Permissions) ->
    case lists:member(PermissionId, Permissions) of
        true -> true;
        false -> list_member(Rest, Permissions)
    end.

drop_seco_tables(SKey) ->
    case have_permission(SKey, manage_system_tables) of
        true ->
            if_drop_table(SKey, ddSeCo),     
            if_drop_table(SKey, ddRole),         
            if_drop_table(SKey, ddAccount);   
        false ->
            ?SecurityException({"Drop seco tables unauthorized", SKey})
    end.

seco_create(SessionId, Name, {AuthMethod,_}) -> 
    SeCo = #ddSeCo{pid=self(), sessionId=SessionId, name=Name, authMethod=AuthMethod, authTime=erlang:now()},
    SKey = erlang:phash2(SeCo), 
    SeCo#ddSeCo{skey=SKey, state=unauthorized}.

seco_register(#ddSeCo{skey=SKey, pid=Pid}=SeCo, AccountId) when Pid == self() -> 
    if_write(SKey, ddSeCo, SeCo#ddSeCo{accountId=AccountId}),
    case if_select_seco_keys_by_pid(#ddSeCo{pid=self(),name= <<"register">>},Pid) of
        {[],true} ->    imem_monitor:monitor(Pid);
        _ ->            ok
    end,
    SKey.    %% hash is returned back to caller

seco_authenticated(SKey) -> 
    case if_read(SKey, ddSeCo, SKey) of
        [#ddSeCo{pid=Pid} = SeCo] when Pid == self() -> 
            SeCo;
        [#ddSeCo{}] ->      
            ?SecurityViolation({"Not logged in", SKey});
        [] ->               
            ?SecurityException({"Not logged in", SKey})
    end.   

seco_authorized(SKey) -> 
    case if_read(SKey, ddSeCo, SKey) of
        [#ddSeCo{pid=Pid, state=authorized} = SeCo] when Pid == self() -> 
            SeCo;
        [#ddSeCo{}] ->      
            ?SecurityViolation({"Not logged in", SKey});
        [] ->               
            ?SecurityException({"Not logged in", SKey})
    end.   

seco_update(#ddSeCo{skey=SKey,pid=Pid}=SeCo, #ddSeCo{skey=SKey,pid=Pid}=SeCoNew) when Pid == self() -> 
    case if_read(SKey, ddSeCo, SKey) of
        [] ->       ?SecurityException({"Not logged in", SKey});
        [SeCo] ->   if_write(SKey, ddSeCo, SeCoNew);
        [_] ->      ?SecurityException({"Security context is modified by someone else", SKey})
    end;
seco_update(#ddSeCo{skey=SKey}, _) -> 
    ?SecurityViolation({"Not logged in", SKey}).

seco_delete(_SKeyM, []) -> ok;
seco_delete(SKeyM, [SKey|SKeys]) ->
    seco_delete(SKeyM, SKey),
    seco_delete(SKeyM, SKeys);    
seco_delete(SKeyM, SKey) ->
    {Keys,true} = if_select_perm_keys_by_skey(SKeyM, SKey), 
    seco_perm_delete(SKeyM, Keys),
    try 
        if_delete(SKeyM, ddSeCo, SKey)
    catch
        Class:Reason -> io:format(user, "~p:seco_delete(~p) - exception ~p:~p~n", [?MODULE, SKey, Class, Reason])
    end.

seco_perm_delete(_SKeyM, []) -> ok;
seco_perm_delete(SKeyM, [PKey|PKeys]) ->
    try
        if_delete(SKeyM, ddPerm, PKey)
    catch
        Class:Reason -> io:format(user, "~p:seco_perm_delete(~p) - exception ~p:~p~n", [?MODULE, PKey, Class, Reason])
    end,
    seco_perm_delete(SKeyM, PKeys).

has_role(SKey, RootRoleId, RoleId) ->
    case have_permission(SKey, manage_accounts) of
        true ->     if_has_role(SKey, RootRoleId, RoleId); 
        false ->    ?SecurityException({"Has role unauthorized",SKey})
    end.

has_permission(SKey, RootRoleId, Permission) ->
    case have_permission(SKey, manage_accounts) of
        true ->     if_has_permission(SKey, RootRoleId, Permission); 
        false ->    ?SecurityException({"Has permission unauthorized",SKey})
    end.

have_role(SKey, RoleId) ->
    #ddSeCo{accountId=AccountId} = seco_authorized(SKey),
    if_has_role(SKey, AccountId, RoleId).

have_permission(SKey, Permission) ->
    #ddSeCo{accountId=AccountId} = seco_authorized(SKey),
    if_has_permission(SKey, AccountId, Permission).

authenticate(SessionId, Name, Credentials) ->
    LocalTime = calendar:local_time(),
    #ddSeCo{skey=SKey} = SeCo = seco_create(SessionId, Name, Credentials),
    case if_select_account_by_name(SKey, Name) of
        {[#ddAccount{locked='true'}],true} ->
            ?SecurityException({"Account is locked. Contact a system administrator", Name});
        {[#ddAccount{lastFailureTime=LocalTime} = Account],true} ->
            %% lie a bit, don't show a fast attacker that this attempt might have worked
            if_write(SKey, ddAccount, Account#ddAccount{lastFailureTime=calendar:local_time(), locked='true'}),
            ?SecurityException({"Invalid account credentials. Please retry", Name});
        {[#ddAccount{id=AccountId, credentials=CredList} = Account],true} -> 
            case lists:member(Credentials,CredList) of
                false ->    if_write(SKey, ddAccount, Account#ddAccount{lastFailureTime=calendar:local_time()}),
                            ?SecurityException({"Invalid account credentials. Please retry", Name});
                true ->     ok=if_write(SKey, ddAccount, Account#ddAccount{lastFailureTime=undefined}),
                            seco_register(SeCo, AccountId)  % return (hash) value to client
            end;
        {[],true} -> 
            ?SecurityException({"Invalid account credentials. Please retry", Name})
    end.

login(SKey) ->
    #ddSeCo{accountId=AccountId, authMethod=AuthenticationMethod} = SeCo = seco_authenticated(SKey),
    LocalTime = calendar:local_time(),
    PwdExpireSecs = calendar:datetime_to_gregorian_seconds(LocalTime),
    PwdExpireDate = calendar:gregorian_seconds_to_datetime(PwdExpireSecs-24*3600*?PASSWORD_VALIDITY),
    case {if_read(SKey, ddAccount, AccountId), AuthenticationMethod} of
        {[#ddAccount{lastPasswordChangeTime=undefined}], pwdmd5} -> 
            logout(SKey),
            ?SecurityException({"Password expired. Please change it", AccountId});
        {[#ddAccount{lastPasswordChangeTime=LastChange}], pwdmd5} when LastChange < PwdExpireDate -> 
            logout(SKey),
            ?SecurityException({"Password expired. Please change it", AccountId});
        {[#ddAccount{}=Account], _} ->
            ok = seco_update(SeCo, SeCo#ddSeCo{state=authorized}),
            if_write(SKey, ddAccount, Account#ddAccount{lastLoginTime=calendar:local_time()}),
            SKey;            
        {[], _} ->                    
            logout(SKey),
            ?SecurityException({"Invalid account credentials. Please retry", AccountId})
    end.

change_credentials(SKey, {pwdmd5,_}=OldCred, {pwdmd5,_}=NewCred) ->
    #ddSeCo{accountId=AccountId} = seco_authenticated(SKey),
    LocalTime = calendar:local_time(),
    [#ddAccount{credentials=CredList} = Account] = if_read(SKey, ddAccount, AccountId),
    if_write(SKey, ddAccount, Account#ddAccount{lastPasswordChangeTime=LocalTime, credentials=[NewCred|lists:delete(OldCred,CredList)]}),
    login(SKey);
change_credentials(SKey, {CredType,_}=OldCred, {CredType,_}=NewCred) ->
    #ddSeCo{accountId=AccountId} = seco_authenticated(SKey),
    [#ddAccount{credentials=CredList} = Account]= if_read(SKey, ddAccount, AccountId),
    if_write(SKey, ddAccount, Account#ddAccount{credentials=[NewCred|lists:delete(OldCred,CredList)]}),
    login(SKey).

logout(SKey) ->
    seco_delete(SKey, SKey).
