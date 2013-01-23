-module(imem_test).

-include("imem_seco.hrl").

%% ----- TESTS ------------------------------------------------

-include_lib("eunit/include/eunit.hrl").

setup() ->
    ?imem_test_setup().

teardown(_) ->
    SKey = ?imem_test_admin_login(),
    catch imem_account:delete(SKey, <<"test">>),
    catch imem_account:delete(SKey, <<"test_admin">>),
    catch imem_role:delete(SKey, table_creator),
    catch imem_role:delete(SKey, test_role),
    catch imem_seco:logout(SKey),
    catch imem_meta:drop_table(user_table_123),
    ?imem_test_teardown().

db_test_() ->
    {
        setup,
        fun setup/0,
        fun teardown/1,
        {with, [
            fun test/1
        ]}}.    

    
test(_) ->
    try
        ClEr = 'ClientError',
        CoEx = 'ConcurrencyException',
        SeEx = 'SecurityException',
        SeVi = 'SecurityViolation',
        % SyEx = 'SystemException',          %% cannot easily test that

        io:format(user, "----TEST--~p~n", [?MODULE]),

        io:format(user, "schema ~p~n", [imem_meta:schema()]),
        io:format(user, "data nodes ~p~n", [imem_meta:data_nodes()]),
        ?assertEqual(true, is_atom(imem_meta:schema())),
        ?assertEqual(true, lists:member({imem_meta:schema(),node()}, imem_meta:data_nodes())),

        io:format(user, "----TEST--~p:test_database~n", [?MODULE]),

        ?assert(1 =< imem_meta:table_size(ddAccount)),       %% pre_generated admin account
        ?assert(1 =< imem_meta:table_size(ddRole)),          %% pre_generated admin role
        ?assert(0 =< imem_meta:table_size(ddSeCo)),
        ?assert(0 =< imem_meta:table_size(ddPerm)),
        ?assert(0 =< imem_meta:table_size(ddQuota)),
        ?assert(6 =< imem_meta:table_size(ddTable)),
        ?assert(0 =< imem_meta:table_size(ddLog@)),
        io:format(user, "success ~p~n", [minimum_table_sizes]),

        io:format(user, "----TEST--~p:test_admin_login~n", [?MODULE]),

        UserId = imem_account:make_id(),
        UserName= <<"test_admin">>,
        UserCred={pwdmd5, erlang:md5(<<"t1e2s3t4_5a6d7m8i9n">>)},
        UserCredNew={pwdmd5, erlang:md5(<<"test_5a6d7m8i9n">>)},
        User = #ddAccount{id=UserId,name=UserName,credentials=[UserCred],fullName= <<"TestAdmin">>},

        SeCoAdmin0=?imem_test_admin_login(),
        io:format(user, "success ~p~n", [admin_login]),
        ?assertEqual(1, imem_sec:table_size(SeCoAdmin0, ddPerm)),    
        ?assertEqual(1, imem_sec:table_size(SeCoAdmin0, ddSeCo)),
        ?assertEqual(2, imem_sec:table_size(SeCoAdmin0, ddPerm)),    
        io:format(user, "success ~p~n", [seco_table_size]), 
        imem_seco ! {'DOWN', simulated_reference, process, self(), simulated_exit},
        timer:sleep(2000),
        ?assertEqual(0, imem_meta:table_size(ddSeCo)),
        io:format(user, "success ~p~n", [seco_table_size]), 
        ?assertException(throw,{'SecurityException',{"Not logged in", SeCoAdmin0}}, imem_sec:table_size(SeCoAdmin0, ddSeCo)),
        ?assertException(throw,{'SecurityException',{"Not logged in", SeCoAdmin0}}, imem_account:create(SeCoAdmin0, User)),
        io:format(user, "success ~p~n", [admin_logged_out]),
        SeCoAdmin1=?imem_test_admin_login(),
        io:format(user, "success ~p~n", [admin_re_login]),
        ?assertEqual(1, imem_sec:table_size(SeCoAdmin1, ddSeCo)),
        io:format(user, "success ~p~n", [seco_table_size]), 
        AllTablesAdmin = imem_sec:all_tables(SeCoAdmin1),
        ?assertEqual(true, lists:member(ddAccount,AllTablesAdmin)),
        ?assertEqual(true, lists:member(ddPerm,AllTablesAdmin)),
        ?assertEqual(true, lists:member(ddQuota,AllTablesAdmin)),
        ?assertEqual(true, lists:member(ddRole,AllTablesAdmin)),
        ?assertEqual(true, lists:member(ddSeCo,AllTablesAdmin)),
        ?assertEqual(true, lists:member(ddTable,AllTablesAdmin)),
        io:format(user, "success ~p~n", [all_tables_admin]), 

        ?assertEqual(ok, imem_account:create(SeCoAdmin1, User)),
        io:format(user, "success ~p~n", [account_create_user]),
        ?assertEqual(ok, imem_role:grant_permission(SeCoAdmin1, UserId, manage_accounts)),
        ?assertEqual(ok, imem_role:grant_permission(SeCoAdmin1, UserId, {ddQuota,select})),
        io:format(user, "success ~p~n", [create_test_admin_permissions]), 
     
        io:format(user, "----TEST--~p:test_authentication~n", [?MODULE]),

        SeCo0=imem_seco:authenticate(someSessionId, UserName, UserCred),
        ?assertEqual(true, is_integer(SeCo0)),
        io:format(user, "success ~p~n", [test_admin_authentication]), 
        ?assertExit({SeVi,{"Not logged in",SeCo0}}, imem_sec:table_size(SeCo0, ddSeCo)),
        io:format(user, "success ~p~n", [table_access_unauthorized]), 
        ?assertException(throw,{SeEx,{?PasswordChangeNeeded, UserId}}, imem_seco:login(SeCo0)),
        io:format(user, "success ~p~n", [new_password]),
        SeCo1=imem_seco:authenticate(someSessionId, UserName, UserCred), 
        ?assertEqual(true, is_integer(SeCo1)),
        io:format(user, "success ~p~n", [test_admin_authentication]), 
        ?assertEqual(SeCo1, imem_seco:change_credentials(SeCo1, UserCred, UserCredNew)),
        io:format(user, "success ~p~n", [password_changed]), 
        ?assertException(throw, {SeEx,{"Select unauthorized",SeCo1}}, imem_sec:table_size(SeCo1, ddSeCo)),
        ?assertException(throw, {SeEx,{"Not logged in",SeCo0}}, imem_sec:table_size(SeCo0, ddSeCo)),
        io:format(user, "success ~p~n", [table_access_rejected_after_logout]),
        AllTablesUser = imem_sec:all_tables(SeCo1),
        ?assertEqual(false, lists:member(ddAccount,AllTablesUser)),
        ?assertEqual(false, lists:member(ddPerm,AllTablesUser)),
        ?assertEqual(true, lists:member(ddQuota,AllTablesUser)),
        ?assertEqual(false, lists:member(ddRole,AllTablesUser)),
        ?assertEqual(false, lists:member(ddSeCo,AllTablesUser)),
        ?assertEqual(false, lists:member(ddTable,AllTablesUser)),
        io:format(user, "success ~p~n", [all_tables_user]), 

        ?assertEqual(true, imem_seco:have_permission(SeCo1, manage_accounts)), 
        ?assertEqual(false, imem_seco:have_permission(SeCo1, manage_bananas)), 
        ?assertEqual(true, imem_seco:have_permission(SeCo1, [manage_accounts])), 
        ?assertEqual(false, imem_seco:have_permission(SeCo1, [manage_bananas])), 
        ?assertEqual(true, imem_seco:have_permission(SeCo1, [manage_accounts,some_unknown_permission])), 
        ?assertEqual(false, imem_seco:have_permission(SeCo1, [manage_bananas,some_unknown_permission])), 
        ?assertEqual(true, imem_seco:have_permission(SeCo1, [some_unknown_permission,manage_accounts])), 
        ?assertEqual(false, imem_seco:have_permission(SeCo1, [some_unknown_permission,manage_bananas])), 
        io:format(user, "success ~p~n", [have_permission]),
        ?assertEqual(ok, imem_seco:logout(SeCo1)),
        io:format(user, "success ~p~n", [logout]), 
        ?assertException(throw, {SeEx,{"Not logged in",SeCo1}}, imem_sec:table_size(SeCo1, ddSeCo)),
        SeCo2=imem_seco:authenticate(someSessionId, UserName, UserCredNew),
        ?assertEqual(true, is_integer(SeCo2)),
        io:format(user, "success ~p~n", [test_admin_reauthentication]),
        ?assertExit({SeVi,{"Not logged in",SeCo2}}, imem_seco:have_permission(SeCo2, manage_bananas)), 
        io:format(user, "success ~p~n", [have_permission_rejected]),
        ?assertEqual(SeCo2, imem_seco:login(SeCo2)),
        io:format(user, "success ~p~n", [login]),
        ?assertEqual(true, imem_seco:have_permission(SeCo2, manage_accounts)), 
        ?assertEqual(false, imem_seco:have_permission(SeCo2, manage_bananas)), 
        io:format(user, "success ~p~n", [have_permission]),
        ?assertException(throw, {SeEx,{"Not logged in",SeCo1}}, imem_seco:have_permission(SeCo1, manage_accounts)), 
        io:format(user, "success ~p~n", [have_permission_rejected]),

        io:format(user, "----TEST--~p:test_manage_accounts~n", [?MODULE]),

        AccountId = imem_account:make_id(),
        AccountCred={pwdmd5, erlang:md5(<<"TestPwd">>)},
        AccountCredNew={pwdmd5, erlang:md5(<<"TestPwd1">>)},
        AccountName= <<"test">>,
        Account = #ddAccount{id=AccountId,name=AccountName,credentials=[AccountCred],fullName= <<"FullName">>},
        AccountId0 = imem_account:make_id(),
        Account0 = #ddAccount{id=AccountId0,name=AccountName,credentials=[AccountCred],fullName= <<"AnotherName">>},
        Account1 = Account#ddAccount{credentials=[AccountCredNew],fullName= <<"NewFullName">>,locked='true'},
        Account2 = Account#ddAccount{credentials=[AccountCredNew],fullName= <<"OldFullName">>},

        SeCo = SeCo2, %% belonging to user <<"test_admin">>

        ?assertEqual(ok, imem_account:create(SeCo, Account)),
        io:format(user, "success ~p~n", [account_create]),
        ?assertException(throw, {ClEr,{"Account already exists",AccountId}}, imem_account:create(SeCo, Account)),
        io:format(user, "success ~p~n", [account_create_already_exists]), 
        ?assertException(throw, {ClEr,{"Account already exists",<<"test">>}}, imem_account:create(SeCo, Account0)),
        io:format(user, "success ~p~n", [account_create_name_already_exists]), 
        ?assertEqual(Account, imem_account:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_get]), 
        ?assertEqual(#ddRole{id=AccountId}, imem_role:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [role_get]), 
        ?assertEqual(ok, imem_account:delete(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_delete]), 
        ?assertEqual(ok, imem_account:delete(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_delete_even_no_exists]), 
        ?assertException(throw, {ClEr,{"Account does not exist", AccountId}}, imem_account:delete(SeCo, Account)),
        io:format(user, "success ~p~n", [account_delete_no_exists]), 
        ?assertEqual(false, imem_account:exists(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_no_exists]), 
        ?assertException(throw, {ClEr,{"Account does not exist", AccountId}}, imem_account:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_get_no_exists]), 
        ?assertException(throw, {ClEr,{"Role does not exist", AccountId}}, imem_role:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [role_get_no_exists]), 
        ?assertEqual(ok, imem_account:create(SeCo, Account)),
        io:format(user, "success ~p~n", [account_create]), 
        ?assertException(throw, {CoEx,{"Account is modified by someone else", AccountId}}, imem_account:delete(SeCo, Account1)),
        io:format(user, "success ~p~n", [account_delete_wrong_version]), 
        ?assertEqual(ok, imem_account:delete(SeCo, AccountName)),
        io:format(user, "success ~p~n", [account_delete_with_check]), 
        ?assertEqual(ok, imem_account:create(SeCo, Account)),
        io:format(user, "success ~p~n", [account_create]), 
        ?assertEqual(true, imem_account:exists(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_exists]), 
        ?assertEqual(Account, imem_account:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_get]), 
        ?assertEqual(#ddRole{id=AccountId}, imem_role:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [role_get]), 
        ?assertEqual(ok, imem_account:update(SeCo, Account, Account1)),
        io:format(user, "success ~p~n", [update_account]), 
        ?assertEqual(Account1, imem_account:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_get_modified]), 
        ?assertException(throw, {CoEx,{"Account is modified by someone else",AccountId}}, imem_account:update(SeCo, Account, Account2)),
        io:format(user, "success ~p~n", [update_account_reject]), 
        ?assertEqual(Account1, imem_account:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [account_get_unchanged]), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, AccountId, manage_accounts)), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, AccountId, manage_bananas)), 
        io:format(user, "success ~p~n", [has_permission]),

        ?assertException(throw,{SeEx,{"Account is locked. Contact a system administrator",<<"test">>}}, imem_seco:authenticate(someSessionId, AccountName, AccountCredNew)), 
        io:format(user, "success ~p~n", [is_locked]),
        ?assertEqual(ok, imem_account:unlock(SeCo, AccountId)),
        io:format(user, "success ~p~n", [unlock]),
        SeCo3=imem_seco:authenticate(someSessionId, AccountName, AccountCredNew),
        ?assertEqual(true, is_integer(SeCo3)),
        io:format(user, "success ~p~n", [test_authentication]),
        ?assertException(throw,{SeEx,{?PasswordChangeNeeded, AccountId}}, imem_seco:login(SeCo3)),
        io:format(user, "success ~p~n", [new_password]),
        SeCo4=imem_seco:authenticate(someSessionId, AccountName, AccountCredNew), 
        ?assertEqual(true, is_integer(SeCo4)),
        io:format(user, "success ~p~n", [test_authentication]), 
        ?assertEqual(SeCo4, imem_seco:change_credentials(SeCo4, AccountCredNew, AccountCred)),
        io:format(user, "success ~p~n", [password_changed]), 
        ?assertEqual(true, imem_seco:have_role(SeCo4, AccountId)), 
        ?assertEqual(false, imem_seco:have_role(SeCo4, some_unknown_role)), 
        ?assertEqual(false, imem_seco:have_permission(SeCo4, manage_accounts)), 
        ?assertEqual(false, imem_seco:have_permission(SeCo4, manage_bananas)), 
        io:format(user, "success ~p~n", [have_permission]),

        io:format(user, "----TEST--~p:test_manage_account_rejectss~n", [?MODULE]),

        ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, imem_sec:drop_table(SeCo4,ddTable)),
        io:format(user, "success ~p~n", [drop_table_table_rejected]), 
        ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, imem_sec:drop_table(SeCo4,ddAccount)),
        io:format(user, "success ~p~n", [drop_account_table_rejected]), 
        ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, imem_sec:drop_table(SeCo4,ddRole)),
        io:format(user, "success ~p~n", [drop_role_table_rejected]), 
        ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, imem_sec:drop_table(SeCo4,ddSeCo)),
        io:format(user, "success ~p~n", [drop_seco_table_rejected]), 
        ?assertException(throw, {SeEx,{"Create account unauthorized",SeCo4}}, imem_account:create(SeCo4, Account)),
        ?assertException(throw, {SeEx,{"Create account unauthorized",SeCo4}}, imem_account:create(SeCo4, Account0)),
        ?assertException(throw, {SeEx,{"Get account unauthorized",SeCo4}}, imem_account:get(SeCo4, AccountId)),
        ?assertException(throw, {SeEx,{"Delete account unauthorized",SeCo4}}, imem_account:delete(SeCo4, AccountId)),
        ?assertException(throw, {SeEx,{"Delete account unauthorized",SeCo4}}, imem_account:delete(SeCo4, Account)),
        ?assertException(throw, {SeEx,{"Exists account unauthorized",SeCo4}}, imem_account:exists(SeCo4, AccountId)),
        ?assertException(throw, {SeEx,{"Get role unauthorized",SeCo4}}, imem_role:get(SeCo4, AccountId)),
        ?assertException(throw, {SeEx,{"Delete account unauthorized",SeCo4}}, imem_account:delete(SeCo4, Account1)),
        ?assertException(throw, {SeEx,{"Update account unauthorized",SeCo4}}, imem_account:update(SeCo4, Account, Account1)),
        ?assertException(throw, {SeEx,{"Update account unauthorized",SeCo4}}, imem_account:update(SeCo4, Account, Account2)),
        io:format(user, "success ~p~n", [unauthorized_rejected]),


        io:format(user, "----TEST--~p:test_manage_account_roles~n", [?MODULE]),

        ?assertEqual(true, imem_seco:has_role(SeCo, AccountId, AccountId)),
        io:format(user, "success ~p~n", [role_has_own_role]), 
        ?assertEqual(false, imem_seco:has_role(SeCo, AccountId, some_unknown_role)),
        io:format(user, "success ~p~n", [role_has_some_unknown_role]), 
        ?assertException(throw, {ClEr,{"Role does not exist", some_unknown_role}}, imem_role:grant_role(SeCo, AccountId, some_unknown_role)),
        io:format(user, "success ~p~n", [role_grant_reject]), 
        ?assertException(throw, {ClEr,{"Role does not exist", some_unknown_role}}, imem_role:grant_role(SeCo, some_unknown_role, AccountId)),
        io:format(user, "success ~p~n", [role_grant_reject]), 
        ?assertEqual(ok, imem_role:create(SeCo, table_creator)),
        io:format(user, "success ~p~n", [role_create_empty_role]), 
        ?assertException(throw, {ClEr,{"Role already exists",table_creator}}, imem_role:create(SeCo, table_creator)),
        io:format(user, "success ~p~n", [role_create_existing_role]), 
        ?assertEqual(false, imem_seco:has_role(SeCo, AccountId, table_creator)),
        io:format(user, "success ~p~n", [role_has_not_tc_role]), 
        ?assertEqual(ok, imem_role:grant_role(SeCo, AccountId, table_creator)),
        io:format(user, "success ~p~n", [role_grant_tc_role]), 
        ?assertEqual(true, imem_seco:has_role(SeCo, AccountId, table_creator)),
        io:format(user, "success ~p~n", [account_has_tc_role]),
        ?assertEqual(false, imem_seco:has_permission(SeCo, AccountId, manage_user_tables)),
        ?assertEqual(false, imem_seco:has_permission(SeCo, AccountId, create_table)),        
        io:format(user, "success ~p~n", [account_has_has_not_roles]),
        ?assertException(throw, {SeEx,{"Create table unauthorized",SeCo4}}, imem_sec:create_table(SeCo4, user_table_123, [a,b,c], [])),
        io:format(user, "success ~p~n", [create_user_table_unauthorized]),
        ?assertEqual(ok, imem_role:grant_permission(SeCo, table_creator, create_table)),
        io:format(user, "success ~p~n", [role_re_grant_tc_role]), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, AccountId, manage_user_tables)),
        ?assertEqual(true, imem_seco:has_permission(SeCo, AccountId, create_table)),        
        ?assertEqual(ok, imem_sec:create_table(SeCo4, user_table_123, [a,b,c], [])),
        io:format(user, "success ~p~n", [create_user_table]),
        ?assertException(throw, {ClEr,{"Table already exists",user_table_123}}, imem_sec:create_table(SeCo4, user_table_123, [a,b,c], [])),
        io:format(user, "success ~p~n", [create_user_table]),
        ?assertEqual(0, imem_sec:table_size(SeCo4, user_table_123)),
        io:format(user, "success ~p~n", [own_table_size]),
        ?assertEqual(#ddRole{id=AccountId,roles=[table_creator]}, imem_role:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [role_get]), 
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, select)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, insert)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, delete)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, update)),
        io:format(user, "success ~p~n", [permissions_own_table]), 
        ?assertEqual(ok, imem_role:revoke_role(SeCo, AccountId, table_creator)),
        io:format(user, "success ~p~n", [role_revoke_tc_role]),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, select)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, insert)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, delete)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, update)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, drop)),
        ?assertEqual(true, imem_sec:have_table_permission(SeCo4, user_table_123, alter)),
        io:format(user, "success ~p~n", [permissions_own_table]),      
        ?assertEqual(#ddRole{id=AccountId,roles=[]}, imem_role:get(SeCo, AccountId)),
        io:format(user, "success ~p~n", [role_get]),
        ?assertEqual(ok, imem_sec:insert(SeCo4, user_table_123, {"A","B","C"})),
        ?assertEqual(1, imem_sec:table_size(SeCo4, user_table_123)),
        io:format(user, "success ~p~n", [insert_own_table]),
        ?assertEqual(ok, imem_sec:insert(SeCo4, user_table_123, {"AA","BB","CC"})),
        ?assertEqual(2, imem_sec:table_size(SeCo4, user_table_123)),
        io:format(user, "success ~p~n", [insert_own_table]),
        ?assertEqual(ok, imem_sec:drop_table(SeCo4, user_table_123)),
        io:format(user, "success ~p~n", [drop_own_table]),
        ?assertException(throw, {'ClientError',{"Table does not exist",user_table_123}}, imem_sec:table_size(SeCo4, user_table_123)),    
        ?assertEqual(ok, imem_role:grant_role(SeCo, AccountId, table_creator)),
        io:format(user, "success ~p~n", [role_grant_tc_role]),      
        ?assertEqual(ok, imem_role:create(SeCo, #ddRole{id=test_role,roles=[],permissions=[perform_tests]})),
        io:format(user, "success ~p~n", [role_create_test_role]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, test_role, perform_tests)),
        io:format(user, "success ~p~n", [role_has_test_permission]), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, test_role, stupid_permission)),
        io:format(user, "success ~p~n", [role_has_stupid_permission]), 
        ?assertEqual(false, imem_seco:has_role(SeCo, AccountId, test_role)),
        io:format(user, "success ~p~n", [role_has_test_role]), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, AccountId, perform_tests)),
        io:format(user, "success ~p~n", [role_has_test_permission]), 
        ?assertEqual(ok, imem_role:grant_role(SeCo, table_creator, test_role)),
        io:format(user, "success ~p~n", [role_grant_test_role]), 
        ?assertEqual(true, imem_seco:has_role(SeCo, AccountId, test_role)),
        io:format(user, "success ~p~n", [role_has_test_role]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, AccountId, perform_tests)),
        ?assertEqual(true, imem_seco:has_permission(SeCo, AccountId, [perform_tests])),
        ?assertEqual(true, imem_seco:has_permission(SeCo, AccountId, [crap1,perform_tests,{crap2,read}])),
        io:format(user, "success ~p~n", [role_has_test_permission]), 

        io:format(user, "----TEST--~p:test_manage_account_role rejects~n", [?MODULE]),

        ?assertException(throw, {SeEx,{"Create role unauthorized",SeCo4}}, imem_role:create(SeCo4, #ddRole{id=test_role,roles=[],permissions=[perform_tests]})),
        ?assertException(throw, {SeEx,{"Create role unauthorized",SeCo4}}, imem_role:create(SeCo4, table_creator)),
        ?assertException(throw, {SeEx,{"Get role unauthorized",SeCo4}}, imem_role:get(SeCo4, AccountId)),
        ?assertException(throw, {SeEx,{"Grant role unauthorized",SeCo4}}, imem_role:grant_role(SeCo4, AccountId, table_creator)),
        ?assertException(throw, {SeEx,{"Grant role unauthorized",SeCo4}}, imem_role:grant_role(SeCo4, AccountId, some_unknown_role)),
        ?assertException(throw, {SeEx,{"Grant role unauthorized",SeCo4}}, imem_role:grant_role(SeCo4, table_creator, test_role)),
        ?assertException(throw, {SeEx,{"Has role unauthorized",SeCo4}}, imem_seco:has_role(SeCo4, AccountId, AccountId)),
        ?assertException(throw, {SeEx,{"Has role unauthorized",SeCo4}}, imem_seco:has_role(SeCo4, AccountId, table_creator)),
        ?assertException(throw, {SeEx,{"Revoke role unauthorized",SeCo4}}, imem_role:revoke_role(SeCo4, AccountId, table_creator)),
        io:format(user, "success ~p~n", [manage_account_roles_rejects]), 

        io:format(user, "----TEST--~p:test_manage_account_permissions~n", [?MODULE]),

        ?assertEqual(ok, imem_role:grant_permission(SeCo, test_role, delete_tests)),
        io:format(user, "success ~p~n", [role_grant_test_role_delete_tests]), 
        ?assertEqual(ok, imem_role:grant_permission(SeCo, test_role, fake_tests)),
        io:format(user, "success ~p~n", [role_grant_test_role_fake_tests]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, AccountId, delete_tests)),
        io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, AccountId, fake_tests)),
        io:format(user, "success ~p~n", [role_has_fake_tests_permission]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, table_creator, delete_tests)),
        io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, table_creator, fake_tests)),
        io:format(user, "success ~p~n", [role_has_fake_tests_permission]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, test_role, delete_tests)),
        io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
        ?assertEqual(true, imem_seco:has_permission(SeCo, test_role, fake_tests)),
        io:format(user, "success ~p~n", [role_has_fake_tests_permission]), 
        ?assertEqual(ok, imem_role:revoke_permission(SeCo, test_role, delete_tests)),
        io:format(user, "success ~p~n", [role_revoke_test_role_delete_tests]), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, AccountId, delete_tests)),
        io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, table_creator, delete_tests)),
        io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
        ?assertEqual(false, imem_seco:has_permission(SeCo, test_role, delete_tests)),
        io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
        ?assertEqual(ok, imem_role:revoke_permission(SeCo, test_role, delete_tests)),
        io:format(user, "success ~p~n", [role_revoket_test_role_delete_tests]), 

        io:format(user, "----TEST--~p:test_manage_account_permission_rejects~n", [?MODULE]),

        ?assertException(throw, {SeEx,{"Has permission unauthorized",SeCo4}}, imem_seco:has_permission(SeCo4, UserId, manage_accounts)), 
        ?assertException(throw, {SeEx,{"Has permission unauthorized",SeCo4}}, imem_seco:has_permission(SeCo4, AccountId, perform_tests)),
        ?assertException(throw, {SeEx,{"Grant permission unauthorized",SeCo4}}, imem_role:grant_permission(SeCo4, test_role, delete_tests)),
        ?assertException(throw, {SeEx,{"Revoke permission unauthorized",SeCo4}}, imem_role:revoke_permission(SeCo4, test_role, delete_tests)),
        io:format(user, "success ~p~n", [test_manage_account_permission_rejects]), 

        io:format(user, "----TEST--~p:test_imem_seco~n", [?MODULE])

        %% Cleanup too dangerous for dev or prod setup
        % ?assertException(throw, {SeEx,{"Drop seco tables unauthorized",SeCo}}, imem_seco:drop_seco_tables(SeCo)),
        % io:format(user, "success ~p~n", [drop_seco_tables_reject]), 
        % ?assertEqual(ok, imem_role:grant_permission(SeCo, UserId, manage_system_tables)),
        % io:format(user, "success ~p~n", [grant_manage_system_tables]),
        % ?assertEqual(ok, imem_seco:drop_seco_tables(SeCo)),
        % io:format(user, "success ~p~n", [drop_seco_tables]), 
        % ?assertEqual(ok, imem_meta:drop_meta_tables()),
        % io:format(user, "success ~p~n", [drop_meta_tables])     
    catch
        Class:Reason ->  io:format(user, "Exception ~p:~p~n~p~n", [Class, Reason, erlang:get_stacktrace()]),
        throw ({Class, Reason})
    end,
    ok.

