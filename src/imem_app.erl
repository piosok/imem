%%% -------------------------------------------------------------------
%%% Author	: Bikram Chatterjee
%%% Description	: 
%%%
%%% Created	: 30.09.2011
%%% -------------------------------------------------------------------

-module(imem_app).

-behaviour(application).

%% --------------------------------------------------------------------
%% Behavioural exports
%% --------------------------------------------------------------------
-export([start/2, stop/1]).

%% --------------------------------------------------------------------
%% Macros
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% Records
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% API Functions
%% --------------------------------------------------------------------


%% ====================================================================!
%% External functions
%% ====================================================================!
%% --------------------------------------------------------------------
%% Func: start/2
%% Returns: {ok, Pid}        |
%%          {ok, Pid, State} |
%%          {error, Reason}
%% --------------------------------------------------------------------
start(_Type, StartArgs) ->
    {ok, CMNode} = application:get_env(erl_cluster_mgr),
    pong = net_adm:ping(CMNode),
    case imem_sup:start_link(StartArgs) of
    	{ok, Pid} ->
    		{ok, Pid};
    	Error ->
    		Error
    end.

%% --------------------------------------------------------------------
%% Func: stop/1
%% Returns: any
%% --------------------------------------------------------------------
stop(_State) ->
	io:format(user, "Stopping ~p~n", [?MODULE]),
	ok.
