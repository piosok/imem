-module(dd_tests).

-include_lib("eunit/include/eunit.hrl").

-include("dd.hrl").


% for test setup only, not exported
if_write(#ddAccount{}=Account) -> 
    imem_if:write(ddAccount, Account);
if_write(#ddRole{}=Role) -> 
    imem_if:write(ddRole, Role).


%% ----- TESTS ------------------------------------------------

setup() -> 
    application:start(imem).

teardown(_) -> 
    application:stop(imem).

account_test_() ->
    {
        setup,
        fun setup/0,
        fun teardown/1,
        {with, [
            fun test/1
            %%, fun test_create_account/1
        ]}}.    

    
test(_) ->

    ClEr = 'ClientError',
    CoEx = 'ConcurrencyException',
    SeEx = 'SecurityException',
    SeVi = 'SecurityViolation',
%    SyEx = 'SystemException',          %% cannot easily test that

    io:format(user, "----TEST--~p:test_mnesia~n", [?MODULE]),

    ?assertEqual("Mnesia", imem_if:schema()),
    io:format(user, "success ~p~n", [schema]),

    io:format(user, "----TEST--~p:test_create_seco_tables~n", [?MODULE]),

    ?assertEqual({atomic,ok}, dd_seco:create_cluster_tables(none)),
    io:format(user, "success ~p~n", [create_cluster_tables]),
    ?assertMatch({aborted,{already_exists,_}}, dd_seco:create_cluster_tables(none)),
    io:format(user, "success ~p~n", [create_account_table_already_exists]),
    ?assertEqual({atomic,ok}, dd_seco:create_local_tables(none)),
    io:format(user, "success ~p~n", [create_cluster_tables]),
    ?assertMatch({aborted,{already_exists,_}}, dd_seco:create_local_tables(none)),
    io:format(user, "success ~p~n", [create_account_table_already_exists]),

    UserId = make_ref(),
    UserName= <<"test_admin">>,
    UserCred={pwdmd5, erlang:md5(<<"t1e2s3t4_5a6d7m8i9n">>)},
    UserCredNew={pwdmd5, erlang:md5(<<"test_5a6d7m8i9n">>)},
    User = #ddAccount{id=UserId,name=UserName,credentials=[UserCred],fullName= <<"TestAdmin">>},

    ?assertEqual(ok, if_write(User)),
    io:format(user, "success ~p~n", [create_test_admin]), 
    ?assertEqual(ok, if_write(#ddRole{id=UserId,roles=[],permissions=[manage_accounts]})),
    io:format(user, "success ~p~n", [create_test_admin_permissions]), 
 
    io:format(user, "----TEST--~p:test_authentification~n", [?MODULE]),

    SeCo0=dd_seco:authenticate(someSessionId, UserName, UserCred),
    ?assertEqual(is_integer(SeCo0), true),
    io:format(user, "success ~p~n", [test_admin_authentification]), 
    ?assertException(throw,{SeEx,{"Password expired. Please change it", UserId}}, dd_seco:login(SeCo0)),
    io:format(user, "success ~p~n", [new_password]),
    SeCo1=dd_seco:authenticate(someSessionId, UserName, UserCred), 
    ?assertEqual(is_integer(SeCo1), true),
    io:format(user, "success ~p~n", [test_admin_authentification]), 
    ?assertEqual(SeCo1, dd_seco:change_credentials(SeCo1, UserCred, UserCredNew)),
    io:format(user, "success ~p~n", [password_changed]), 
    ?assertEqual(true, dd_seco:have_permission(SeCo1, manage_accounts)), 
    ?assertEqual(false, dd_seco:have_permission(SeCo1, manage_bananas)), 
    ?assertEqual(true, dd_seco:have_permission(SeCo1, [manage_accounts])), 
    ?assertEqual(false, dd_seco:have_permission(SeCo1, [manage_bananas])), 
    ?assertEqual(true, dd_seco:have_permission(SeCo1, [manage_accounts,some_unknown_permission])), 
    ?assertEqual(false, dd_seco:have_permission(SeCo1, [manage_bananas,some_unknown_permission])), 
    ?assertEqual(true, dd_seco:have_permission(SeCo1, [some_unknown_permission,manage_accounts])), 
    ?assertEqual(false, dd_seco:have_permission(SeCo1, [some_unknown_permission,manage_bananas])), 
    io:format(user, "success ~p~n", [have_permission]),
    ?assertEqual(ok, dd_seco:logout(SeCo1)),
    io:format(user, "success ~p~n", [logout]), 
    SeCo2=dd_seco:authenticate(someSessionId, UserName, UserCredNew),
    ?assertEqual(is_integer(SeCo2), true),
    io:format(user, "success ~p~n", [test_admin_reauthentification]),
    ?assertExit({SeVi,{"Invalid security context",SeCo2}}, dd_seco:have_permission(SeCo2, manage_bananas)), 
    io:format(user, "success ~p~n", [have_permission_rejected]),
    ?assertEqual(SeCo2, dd_seco:login(SeCo2)),
    io:format(user, "success ~p~n", [login]),
    ?assertEqual(true, dd_seco:have_permission(SeCo2, manage_accounts)), 
    ?assertEqual(false, dd_seco:have_permission(SeCo2, manage_bananas)), 
    io:format(user, "success ~p~n", [have_permission]),
    ?assertException(throw, {SeEx,{"Security context does not exist",SeCo1}}, dd_seco:have_permission(SeCo1, manage_accounts)), 
    io:format(user, "success ~p~n", [have_permission_rejected]),

    io:format(user, "----TEST--~p:test_manage_accounts~n", [?MODULE]),

    AccountId = make_ref(),
    AccountCred={pwdmd5, erlang:md5(<<"TestPwd">>)},
    AccountCredNew={pwdmd5, erlang:md5(<<"TestPwd1">>)},
    AccountName= <<"test">>,
    Account = #ddAccount{id=AccountId,name=AccountName,credentials=[AccountCred],fullName= <<"FullName">>},
    AccountId0 = make_ref(),
    Account0 = #ddAccount{id=AccountId0,name=AccountName,credentials=[AccountCred],fullName= <<"AnotherName">>},
    Account1 = Account#ddAccount{credentials=[AccountCredNew],fullName= <<"NewFullName">>,locked='true'},
    Account2 = Account#ddAccount{credentials=[AccountCredNew],fullName= <<"OldFullName">>},

    SeCo = SeCo2, %% belonging to user <<"test_admin">>

    ?assertEqual(ok, dd_account:create(SeCo, Account)),
    io:format(user, "success ~p~n", [account_create]),
    ?assertException(throw, {ClEr,{"Account already exists",AccountId}}, dd_account:create(SeCo, Account)),
    io:format(user, "success ~p~n", [account_create_already_exists]), 
    ?assertException(throw, {ClEr,{"Account name already exists for",<<"test">>}}, dd_account:create(SeCo, Account0)),
    io:format(user, "success ~p~n", [account_create_name_already_exists]), 
    ?assertEqual(Account, dd_account:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_get]), 
    ?assertEqual(#ddRole{id=AccountId}, dd_role:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [role_get]), 
    ?assertEqual(ok, dd_account:delete(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_delete]), 
    ?assertEqual(ok, dd_account:delete(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_delete_even_no_exists]), 
    ?assertException(throw, {ClEr,{"Account does not exist", AccountId}}, dd_account:delete(SeCo, Account)),
    io:format(user, "success ~p~n", [account_delete_no_exists]), 
    ?assertEqual(false, dd_account:exists(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_no_exists]), 
    ?assertException(throw, {ClEr,{"Account does not exist", AccountId}}, dd_account:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_get_no_exists]), 
    ?assertException(throw, {ClEr,{"Role does not exist", AccountId}}, dd_role:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [role_get_no_exists]), 
    ?assertEqual(ok, dd_account:create(SeCo, Account)),
    io:format(user, "success ~p~n", [account_create]), 
    ?assertException(throw, {CoEx,{"Account is modified by someone else", AccountId}}, dd_account:delete(SeCo, Account1)),
    io:format(user, "success ~p~n", [account_delete_wrong_version]), 
    ?assertEqual(ok, dd_account:delete(SeCo, Account)),
    io:format(user, "success ~p~n", [account_delete_with_check]), 
    ?assertEqual(ok, dd_account:create(SeCo, Account)),
    io:format(user, "success ~p~n", [account_create]), 
    ?assertEqual(true, dd_account:exists(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_exists]), 
    ?assertEqual(Account, dd_account:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_get]), 
    ?assertEqual(#ddRole{id=AccountId}, dd_role:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [role_get]), 
    ?assertEqual(ok, dd_account:update(SeCo, Account, Account1)),
    io:format(user, "success ~p~n", [update_account]), 
    ?assertEqual(Account1, dd_account:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_get_modified]), 
    ?assertException(throw, {CoEx,{"Account is modified by someone else",AccountId}}, dd_account:update(SeCo, Account, Account2)),
    io:format(user, "success ~p~n", [update_account_reject]), 
    ?assertEqual(Account1, dd_account:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [account_get_unchanged]), 
    ?assertEqual(false, dd_seco:has_permission(SeCo, AccountId, manage_accounts)), 
    ?assertEqual(false, dd_seco:has_permission(SeCo, AccountId, manage_bananas)), 
    io:format(user, "success ~p~n", [has_permission]),

    ?assertException(throw,{SeEx,{"Account is locked. Contact a system administrator",<<"test">>}}, dd_seco:authenticate(someSessionId, AccountName, AccountCredNew)), 
    io:format(user, "success ~p~n", [is_locked]),
    ?assertEqual(ok, dd_account:unlock(SeCo, AccountId)),
    io:format(user, "success ~p~n", [unlock]),
    SeCo3=dd_seco:authenticate(someSessionId, AccountName, AccountCredNew),
    ?assertEqual(is_integer(SeCo3), true),
    io:format(user, "success ~p~n", [test_authentification]),
    ?assertException(throw,{SeEx,{"Password expired. Please change it", AccountId}}, dd_seco:login(SeCo3)),
    io:format(user, "success ~p~n", [new_password]),
    SeCo4=dd_seco:authenticate(someSessionId, AccountName, AccountCredNew), 
    ?assertEqual(is_integer(SeCo4), true),
    io:format(user, "success ~p~n", [test_authentification]), 
    ?assertEqual(SeCo4, dd_seco:change_credentials(SeCo4, AccountCredNew, AccountCred)),
    io:format(user, "success ~p~n", [password_changed]), 
    ?assertEqual(true, dd_seco:have_role(SeCo4, AccountId)), 
    ?assertEqual(false, dd_seco:have_role(SeCo4, some_unknown_role)), 
    ?assertEqual(false, dd_seco:have_permission(SeCo4, manage_accounts)), 
    ?assertEqual(false, dd_seco:have_permission(SeCo4, manage_bananas)), 
    io:format(user, "success ~p~n", [have_permission]),

    io:format(user, "----TEST--~p:test_manage_account_rejectss~n", [?MODULE]),

    ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, dd_seco:drop_table(SeCo4,ddTable)),
    io:format(user, "success ~p~n", [drop_table_table_rejected]), 
    ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, dd_seco:drop_table(SeCo4,ddAccount)),
    io:format(user, "success ~p~n", [drop_account_table_rejected]), 
    ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, dd_seco:drop_table(SeCo4,ddRole)),
    io:format(user, "success ~p~n", [drop_role_table_rejected]), 
    ?assertException(throw, {SeEx,{"Drop system table unauthorized",SeCo4}}, dd_seco:drop_table(SeCo4,ddSeCo)),
    io:format(user, "success ~p~n", [drop_seco_table_rejected]), 
    ?assertException(throw, {SeEx,{"Create account unauthorized",SeCo4}}, dd_account:create(SeCo4, Account)),
    ?assertException(throw, {SeEx,{"Create account unauthorized",SeCo4}}, dd_account:create(SeCo4, Account0)),
    ?assertException(throw, {SeEx,{"Get account unauthorized",SeCo4}}, dd_account:get(SeCo4, AccountId)),
    ?assertException(throw, {SeEx,{"Delete account unauthorized",SeCo4}}, dd_account:delete(SeCo4, AccountId)),
    ?assertException(throw, {SeEx,{"Delete account unauthorized",SeCo4}}, dd_account:delete(SeCo4, Account)),
    ?assertException(throw, {SeEx,{"Exists account unauthorized",SeCo4}}, dd_account:exists(SeCo4, AccountId)),
    ?assertException(throw, {SeEx,{"Get role unauthorized",SeCo4}}, dd_role:get(SeCo4, AccountId)),
    ?assertException(throw, {SeEx,{"Delete account unauthorized",SeCo4}}, dd_account:delete(SeCo4, Account1)),
    ?assertException(throw, {SeEx,{"Update account unauthorized",SeCo4}}, dd_account:update(SeCo4, Account, Account1)),
    ?assertException(throw, {SeEx,{"Update account unauthorized",SeCo4}}, dd_account:update(SeCo4, Account, Account2)),
    io:format(user, "success ~p~n", [unauthorized_rejected]),


    io:format(user, "----TEST--~p:test_manage_account_roles~n", [?MODULE]),

    ?assertEqual(true, dd_seco:has_role(SeCo, AccountId, AccountId)),
    io:format(user, "success ~p~n", [role_has_own_role]), 
    ?assertEqual(false, dd_seco:has_role(SeCo, AccountId, some_unknown_role)),
    io:format(user, "success ~p~n", [role_has_some_unknown_role]), 
    ?assertException(throw, {ClEr,{"Role does not exist", some_unknown_role}}, dd_role:grant_role(SeCo, AccountId, some_unknown_role)),
    io:format(user, "success ~p~n", [role_grant_reject]), 
    ?assertException(throw, {ClEr,{"Role does not exist", some_unknown_role}}, dd_role:grant_role(SeCo, some_unknown_role, AccountId)),
    io:format(user, "success ~p~n", [role_grant_reject]), 
    ?assertEqual(ok, dd_role:create(SeCo, admin)),
    io:format(user, "success ~p~n", [role_create_empty_role]), 
    ?assertException(throw, {ClEr,{"Role already exists",admin}}, dd_role:create(SeCo, admin)),
    io:format(user, "success ~p~n", [role_create_existing_role]), 
    ?assertEqual(false, dd_seco:has_role(SeCo, AccountId, admin)),
    io:format(user, "success ~p~n", [role_has_not_admin_role]), 
    ?assertEqual(ok, dd_role:grant_role(SeCo, AccountId, admin)),
    io:format(user, "success ~p~n", [role_grant_admin_role]), 
    ?assertEqual(true, dd_seco:has_role(SeCo, AccountId, admin)),
    io:format(user, "success ~p~n", [role_has_admin_role]), 
    ?assertEqual(ok, dd_role:grant_role(SeCo, AccountId, admin)),
    io:format(user, "success ~p~n", [role_re_grant_admin_role]), 
    ?assertEqual(#ddRole{id=AccountId,roles=[admin]}, dd_role:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [role_get]), 
    ?assertEqual(ok, dd_role:revoke_role(SeCo, AccountId, admin)),
    io:format(user, "success ~p~n", [role_revoke_admin_role]), 
    ?assertEqual(#ddRole{id=AccountId,roles=[]}, dd_role:get(SeCo, AccountId)),
    io:format(user, "success ~p~n", [role_get]),
    ?assertEqual(ok, dd_role:grant_role(SeCo, AccountId, admin)),
    io:format(user, "success ~p~n", [role_grant_admin_role]),      
    ?assertEqual(ok, dd_role:create(SeCo, #ddRole{id=test_role,roles=[],permissions=[perform_tests]})),
    io:format(user, "success ~p~n", [role_create_test_role]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, test_role, perform_tests)),
    io:format(user, "success ~p~n", [role_has_test_permission]), 
    ?assertEqual(false, dd_seco:has_permission(SeCo, test_role, stupid_permission)),
    io:format(user, "success ~p~n", [role_has_stupid_permission]), 
    ?assertEqual(false, dd_seco:has_role(SeCo, AccountId, test_role)),
    io:format(user, "success ~p~n", [role_has_test_role]), 
    ?assertEqual(false, dd_seco:has_permission(SeCo, AccountId, perform_tests)),
    io:format(user, "success ~p~n", [role_has_test_permission]), 
    ?assertEqual(ok, dd_role:grant_role(SeCo, admin, test_role)),
    io:format(user, "success ~p~n", [role_grant_test_role]), 
    ?assertEqual(true, dd_seco:has_role(SeCo, AccountId, test_role)),
    io:format(user, "success ~p~n", [role_has_test_role]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, AccountId, perform_tests)),
    ?assertEqual(true, dd_seco:has_permission(SeCo, AccountId, [perform_tests])),
    ?assertEqual(true, dd_seco:has_permission(SeCo, AccountId, [crap1,perform_tests,{crap2,read}])),
    io:format(user, "success ~p~n", [role_has_test_permission]), 

    io:format(user, "----TEST--~p:test_manage_account_role rejects~n", [?MODULE]),

    ?assertException(throw, {SeEx,{"Create role unauthorized",SeCo4}}, dd_role:create(SeCo4, #ddRole{id=test_role,roles=[],permissions=[perform_tests]})),
    ?assertException(throw, {SeEx,{"Create role unauthorized",SeCo4}}, dd_role:create(SeCo4, admin)),
    ?assertException(throw, {SeEx,{"Get role unauthorized",SeCo4}}, dd_role:get(SeCo4, AccountId)),
    ?assertException(throw, {SeEx,{"Grant role unauthorized",SeCo4}}, dd_role:grant_role(SeCo4, AccountId, admin)),
    ?assertException(throw, {SeEx,{"Grant role unauthorized",SeCo4}}, dd_role:grant_role(SeCo4, AccountId, some_unknown_role)),
    ?assertException(throw, {SeEx,{"Grant role unauthorized",SeCo4}}, dd_role:grant_role(SeCo4, admin, test_role)),
    ?assertException(throw, {SeEx,{"Has role unauthorized",SeCo4}}, dd_seco:has_role(SeCo4, AccountId, AccountId)),
    ?assertException(throw, {SeEx,{"Has role unauthorized",SeCo4}}, dd_seco:has_role(SeCo4, AccountId, admin)),
    ?assertException(throw, {SeEx,{"Revoke role unauthorized",SeCo4}}, dd_role:revoke_role(SeCo4, AccountId, admin)),
    io:format(user, "success ~p~n", [manage_account_roles_rejects]), 

    io:format(user, "----TEST--~p:test_manage_account_permissions~n", [?MODULE]),

    ?assertEqual(ok, dd_role:grant_permission(SeCo, test_role, delete_tests)),
    io:format(user, "success ~p~n", [role_grant_test_role_delete_tests]), 
    ?assertEqual(ok, dd_role:grant_permission(SeCo, test_role, fake_tests)),
    io:format(user, "success ~p~n", [role_grant_test_role_fake_tests]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, AccountId, delete_tests)),
    io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, AccountId, fake_tests)),
    io:format(user, "success ~p~n", [role_has_fake_tests_permission]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, admin, delete_tests)),
    io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, admin, fake_tests)),
    io:format(user, "success ~p~n", [role_has_fake_tests_permission]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, test_role, delete_tests)),
    io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
    ?assertEqual(true, dd_seco:has_permission(SeCo, test_role, fake_tests)),
    io:format(user, "success ~p~n", [role_has_fake_tests_permission]), 
    ?assertEqual(ok, dd_role:revoke_permission(SeCo, test_role, delete_tests)),
    io:format(user, "success ~p~n", [role_revoke_test_role_delete_tests]), 
    ?assertEqual(false, dd_seco:has_permission(SeCo, AccountId, delete_tests)),
    io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
    ?assertEqual(false, dd_seco:has_permission(SeCo, admin, delete_tests)),
    io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
    ?assertEqual(false, dd_seco:has_permission(SeCo, test_role, delete_tests)),
    io:format(user, "success ~p~n", [role_has_delete_tests_permission]), 
    ?assertEqual(ok, dd_role:revoke_permission(SeCo, test_role, delete_tests)),
    io:format(user, "success ~p~n", [role_revoket_test_role_delete_tests]), 

    io:format(user, "----TEST--~p:test_manage_account_permission_rejects~n", [?MODULE]),

    ?assertException(throw, {SeEx,{"Has permission unauthorized",SeCo4}}, dd_seco:has_permission(SeCo4, UserId, manage_accounts)), 
    ?assertException(throw, {SeEx,{"Has permission unauthorized",SeCo4}}, dd_seco:has_permission(SeCo4, AccountId, perform_tests)),
    ?assertException(throw, {SeEx,{"Grant permission unauthorized",SeCo4}}, dd_role:grant_permission(SeCo4, test_role, delete_tests)),
    ?assertException(throw, {SeEx,{"Revoke permission unauthorized",SeCo4}}, dd_role:revoke_permission(SeCo4, test_role, delete_tests)),
    io:format(user, "success ~p~n", [test_manage_account_permission_rejects]), 


    %% Cleanup only if we arrive at this point
    ?assertException(throw, {SeEx,{"Drop system tables unauthorized",SeCo}}, dd_seco:drop_system_tables(SeCo)),
    io:format(user, "success ~p~n", [drop_system_tables_reject]), 
    ?assertEqual(ok, dd_role:grant_permission(SeCo, UserId, manage_system_tables)),
    io:format(user, "success ~p~n", [grant_manage_system_tables]), 
    ?assertEqual({atomic,ok}, dd_seco:drop_system_tables(SeCo)),
    io:format(user, "success ~p~n", [drop_cluster_tables]), 
    ok.

