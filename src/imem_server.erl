-module(imem_server).
-behaviour(ranch_protocol).

-include("imem.hrl").

-export([ start_link/4
        , start_link/1
        , start/0
        , stop/0
        , restart/0
        , init/4
        , send_resp/2
        , mfa/2
        ]).
 
start_link(Params) ->
    Interface   = proplists:get_value(tcp_ip,Params),
    ListenPort  = proplists:get_value(tcp_port,Params),
    SSL         = proplists:get_value(ssl,Params),
    Pwd         = proplists:get_value(pwd,Params),
    {THandler, Opts} = if length(SSL) > 0 -> {ranch_ssl, SSL};
                          true -> {ranch_tcp, []}
                       end,
    case inet:getaddr(Interface, inet) of
        {error, Reason} ->
            ?Error("~p failed to start ~p~n", [?MODULE, Reason]),
            {error, Reason};
        {ok, ListenIf} when is_integer(ListenPort) ->
            NewOpts = lists:foldl(
                        fun({K, V}, Acc) ->
                          case K of
                              certfile ->
                                  [{K, filename:join([Pwd, V])} | Acc];
                              keyfile ->
                                  [{K, filename:join([Pwd, V])} | Acc];
                              _ -> [{K, V} | Acc]
                          end
                        end
                        , []
                        , Opts),
            ?Info("~p starting...~n", [?MODULE]),
            case ranch:start_listener(
                   ?MODULE, 1, THandler,
                   [{ip, ListenIf}, {port, ListenPort} | NewOpts], ?MODULE,
                   if THandler =:= ranch_ssl -> [ssl]; true -> [] end) of
                {ok, _} = Success ->
                ?Info("~p started, listening~s on ~s:~p~n",
                      [?MODULE, if THandler =:= ranch_ssl -> "(ssl)"; true -> "" end,
                       inet:ntoa(ListenIf), ListenPort]),
                ?Info("options ~p~n", [NewOpts]),
                    Success;
                Error ->
                    ?Error("~p failed to start~n~p~n", [?MODULE, Error]),
                    Error
            end;
        _ ->
            {stop, disabled}
    end.

start_link(ListenerPid, Socket, Transport, Opts) ->
    Pid = spawn_opt(?MODULE, init, [ListenerPid, Socket, Transport, Opts],
                    [link, {fullsweep_after, 0}]),
    {ok, Pid}.

start() ->
    {ok, TcpIf} = application:get_env(imem, tcp_ip),
    {ok, TcpPort} = application:get_env(imem, tcp_port),
    {ok, SSL} = application:get_env(imem, ssl),
    Pwd = case code:lib_dir(imem) of {error, _} -> "."; Path -> Path end,
    start_link([{tcp_ip, TcpIf},{tcp_port, TcpPort},{pwd, Pwd}, {ssl, SSL}]).

stop() -> ranch:stop_listener(?MODULE).

restart() ->
    stop(),
    start().
 
init(ListenerPid, Socket, Transport, Opts) ->
    PeerNameMod = case lists:member(ssl, Opts) of true -> ssl; _ -> inet end,
    {ok, {Address, Port}} = PeerNameMod:peername(Socket),
    Str = lists:flatten(io_lib:format("~p received connection from ~s:~p"
                                      , [self(), inet_parse:ntoa(Address)
                                         , Port])),
    ?Debug(Str++"~n", []),
    imem_meta:log_to_db(debug,?MODULE,init
                        ,[ListenerPid, Socket, Transport, Opts], Str),
    ok = ranch:accept_ack(ListenerPid),
    % Linkinking TCP socket
    % for easy lookup
    erlang:link(
      case lists:member(ssl, Opts) of
          true ->
              {sslsocket,{gen_tcp,TcpSocket,tls_connection,_},_} = Socket,
              TcpSocket;
          _ -> Socket
      end),
    loop(Socket, Transport, <<>>, 0).

-define(TLog(__F, __A), ok). 
%-define(TLog(__F, __A), ?Info(__F, __A)). 
loop(Socket, Transport, Buf, Len) ->
    {OK, Closed, Error} = Transport:messages(),
    Transport:setopts(Socket, [{active, once}]),   
    receive
        {OK, Socket, Data} ->
            {NewLen, NewBuf} =
                if Buf =:= <<>> ->
                    << L:32, PayLoad/binary >> = Data,
                    ?TLog(" term size ~p~n", [<< L:32 >>]),
                    {L, PayLoad};
                true -> {Len, <<Buf/binary, Data/binary>>}
            end,
            case {byte_size(NewBuf), NewLen} of
                {NewLen, NewLen} ->
                    case (catch binary_to_term(NewBuf)) of
                        {'EXIT', _} ->
                            ?Info(" [MALFORMED] ~p received ~p bytes buffering...", [self(), byte_size(NewBuf)]),
                            loop(Socket, Transport, NewBuf, NewLen);
                        Term ->
                            if element(2, Term) =:= imem_sec ->
                                ?TLog("mfa ~p", [Term]),
                                mfa(Term, {Transport, Socket, element(1, Term)});
                            true ->
                                send_resp({error, {"security breach attempt", Term}}, {Transport, Socket, element(1, Term)})
                            end,
                            TSize = byte_size(term_to_binary(Term)),
                            RestSize = byte_size(NewBuf)-TSize,
                            loop(Socket, Transport, binary_part(NewBuf, {TSize, RestSize}), NewLen)
                    end;
                _ ->
                    ?Info(" [INCOMPLETE] ~p received ~p bytes buffering...", [self(), byte_size(NewBuf)]),
                    loop(Socket, Transport, NewBuf, NewLen)
            end;
        {Closed, Socket} ->
            ?Debug("socket ~p got closed!~n", [Socket]);
        {Error, Socket, Reason} ->
            ?Error("socket ~p error: ~p", [Socket, Reason]);
        close ->
            ?Warn("closing socket...~n", [Socket]),
            Transport:close(Socket)
    end.

mfa({Ref, Mod, which_applications, Args}, Transport) when Mod =:= imem_sec;
                                                          Mod =:= imem_meta ->
    mfa({Ref, application, which_applications, Args}, Transport);
mfa({Ref, Mod, Fun, Args}, Transport) ->
    NewArgs = args(Ref,Fun,Args,Transport),
    ApplyRes = try
                   ?TLog("~p MFA -> R ~n ~p:~p(~p)~n", [Transport,Mod,Fun,NewArgs]),
                   apply(Mod,Fun,NewArgs)
               catch 
                    _Class:Reason -> {error, {Reason, erlang:get_stacktrace()}}
               end,
    ?TLog("~p MFA -> R ~n ~p:~p(~p) -> ~p~n", [Transport,Mod,Fun,NewArgs,ApplyRes]),
    ?TLog("~p MF -> R ~n ~p:~p -> ~p~n", [Transport,Mod,Fun,ApplyRes]),
    send_resp(ApplyRes, Transport),
    ok. % 'ok' returned for erlimem compatibility

args(R, fetch_recs_async, A, {_,_,R} = T) ->
    Args = lists:sublist(A, length(A)-1) ++ [T],
    ?TLog("fetch_recs_async, Args for TCP~n ~p~n", [Args]),
    Args;
args(R, fetch_recs_async, A, {_,R} = T) ->
    Args = lists:sublist(A, length(A)-1) ++ [T],
    ?TLog("fetch_recs_async, Args for direct~n ~p~n", [Args]),
    Args;
args(_, _F, A, _) ->
    ?TLog("~p(~p)~n", [_F, A]),
    A.

send_resp(Resp, {Transport, Socket, Ref}) ->
    RespBin = term_to_binary({Ref, Resp}),
    ?TLog("TX (~p)~n~p~n", [byte_size(RespBin), RespBin]),
    PayloadSize = byte_size(RespBin),
    Transport:send(Socket, << PayloadSize:32, RespBin/binary >>);
send_resp(Resp, {Pid, Ref}) when is_pid(Pid) ->
    Pid ! {Ref, Resp}.
