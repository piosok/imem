-module(imem_auth_smsott).

-include("imem_seco.hrl").

-define(TOKEN_TYPES, [<<"SHORT_NUMERIC">>, <<"SHORT_ALPHANUMERIC">>, <<"SHORT_SMALL_AND_CAPITAL">>, <<"LONG_CRYPTIC">>]).

% Example options : http://erlang.org/doc/man/httpc.html#set_options-2
% [{proxy,{undefined,[]}},
%  {https_proxy,{{"localhost",1},[]}},
%  ...
% {socket_opts,[]}]}
-define(HTTP_PROFILE(__AppId), ?GET_CONFIG(smsTokenValidationHttpProfile, [__AppId], smsott)).
-define(HTTP_OPTS(__AppId), ?GET_CONFIG(smsTokenValidationHttpOpts, [__AppId], [])).

-define(HTTP_SOAP_PROFILE(__AppId), ?GET_CONFIG(smsTokenValidationHttpSoapProfile, [__AppId], soapsmsott)).
-define(HTTP_SOAP_OPTS(__AppId), ?GET_CONFIG(smsTokenValidationHttpSoapOpts, [__AppId], [])).

-export([ send_sms_token/3
        , sc_soap_send_sms_token/2
        , verify_sms_token/4
        ]).

-spec send_sms_token(atom(), binary(), ddCredRequest()) ->
    ok | no_return().
send_sms_token(AppId, To, {smsott,Map}) when Map == #{} ->
    sc_send_sms_token(AppId, To);
send_sms_token(_AppId, _To, _DDCredRequest) ->
    error("Unimplemented").

-spec verify_sms_token(atom(), binary(), list() | integer() | binary(), ddCredRequest()) ->
    ok | no_return().
verify_sms_token(AppId, To, Token, {smsott,Map}) when Map == #{} ->
    sc_verify_sms_token(AppId, To, Token);
verify_sms_token(_AppId, _To, _Token, _DDCredRequest) ->
    error("Unimplemented").

% @doc
sc_soap_send_sms_token(AppId,To) ->
    sc_send_sms_token( ?GET_CONFIG(smsTokenValidationSoapServiceUrl,[AppId],"https://host:port/sendSoapSmsToken")
                     , ?GET_CONFIG(smsTokenSoapServiceParsms,[AppId],{"user","password","xmlns"})
                     , ?GET_CONFIG(smsTokenSoapServiceFromMSISDN,[AppId],"+41790000000")
                     , To
                     , ?GET_CONFIG(smsTokenValidationText, [AppId], <<"Imem verification code: %TOKEN% \r\nThis token will expire in 2 Minutes.">>)
                     , ?GET_CONFIG(smsTokenValidationTokenType,[AppId],<<"SHORT_NUMERIC">>)
                     , ?GET_CONFIG(smsTokenValidationExpireTime,[AppId],180)
                     , ?GET_CONFIG(smsTokenValidationTTL,[AppId],180)
                     , ?GET_CONFIG(smsTokenValidationTokenLength,[AppId],6)
                     , imem_client:get_profile(httpc, ?HTTP_SOAP_PROFILE(AppId), ?HTTP_SOAP_OPTS(AppId))
                     ).

sc_send_sms_token(AppId,To) ->
    sc_send_sms_token( AppId
                     , To
                     , ?GET_CONFIG(smsTokenValidationText, [AppId], <<"Imem verification code: %TOKEN% \r\nThis token will expire in 2 Minutes.">>)
                     , ?GET_CONFIG(smsTokenValidationTokenType,[AppId],<<"SHORT_NUMERIC">>)
                     , ?GET_CONFIG(smsTokenValidationExpireTime,[AppId],120)
                     , ?GET_CONFIG(smsTokenValidationTokenLength,[AppId],6)
                     , imem_client:get_profile(httpc, ?HTTP_PROFILE(AppId), ?HTTP_OPTS(AppId))
                     ).

sc_send_sms_token(AppId, To, Text, TokenType, ExpireTime, TokenLength, Profile) ->
    sc_send_sms_token( ?GET_CONFIG(smsTokenValidationServiceUrl,[AppId],"https://api.swisscom.com/v1/tokenvalidation")
                     , ?GET_CONFIG(smsTokenValidationClientId,[AppId],"RokAOeF59nkcFg2GtgxgOdZzosQW1MPQ")
                     , To
                     , Text
                     , TokenType
                     , ExpireTime
                     , TokenLength
                     , ?GET_CONFIG(smsTokenValidationTraceId,[AppId],"IMEM")
                     , Profile
                     ).

sc_send_sms_token(Url, ClientId, To, Text, TokenType, ExpireTime, TokenLength, TraceId, Profile)
when is_integer(ExpireTime), is_integer(TokenLength) ->
    case lists:member(TokenType, ?TOKEN_TYPES) of
        true -> 
            ReqMap = #{to=>To, text=>Text, tokenType=>TokenType, expireTime=>integer_to_binary(ExpireTime), tokenLength=>TokenLength},
            Req = imem_json:encode(if TraceId /= <<>> -> maps:put(traceId, TraceId, ReqMap); true -> ReqMap end),
            ?Debug("Sending sms token ~p", [Req]),
            case httpc:request( post
                              , { Url
                                , [ {"client_id",ClientId}
                                  , {"Accept","application/json; charset=utf-8"}
                                  ]
                                , "application/json; charset=utf-8"
                                , Req
                                }
                              , [{ssl,[{verify,0}]}]
                              , [{full_result, false}]
                              , Profile) of
                {ok,{200,[]}} ->    ok;
                {ok,{400,Body}} ->  error({"HTTP 400", Body});
                {ok,{401,_}} ->     error("HTTP 401: Unauthorized");
                {ok,{403,_}} ->     error("HTTP 403: Client IP not whitelisted");
                {ok,{404,_}} ->     error("HTTP 404: Wrong URL or the given customer not found");
                {ok,{500,Body}} ->  error({"HTTP 500", Body});
                {error, Error} ->   error(Error);
                Error ->            error(Error)
            end;
        _ ->    
            error({"Invalid token type", TokenType})
    end.

sc_send_sms_token(Url, {User, Password, XMLNs}, From, To, Text, TokenType,
                  TTESec, TTLSec, TokenLength, Profile) ->
    case lists:member(TokenType, ?TOKEN_TYPES) of
        true ->
            Req = list_to_binary([
                    "<sendSmsToken xmlns=\"",XMLNs,"\">"
                        "<recipient>",To,"</recipient>"
                        "<from>",From,"</from>"
                        "<text>",Text,"</text>"
                        "<tokenType>",TokenType,"</tokenType>"
                        "<timeToExpiredSeconds>",TTESec,"</timeToExpiredSeconds>"
                        "<timeToLiveSeconds>",TTLSec,"</timeToLiveSeconds>"
                        "<tokenlength>",TokenLength,"</tokenlength>"
                    "</sendSmsToken>"]),
            ?Debug("Sending sms token ~p", [Req]),
            Authorization = "Basic "++binary_to_list(base64:encode(User++":"++Password)),
            case httpc:request(post, {Url, [{"Authorization",Authorization}],
                                      "application/xml;charset=UTF-8", Req},
                               [{ssl,[{verify,0}]}], [{full_result, false}],
                               Profile) of
                {ok,{200,[]}} ->    ok;
                {ok,{Other,Body}} ->  error({"HTTP", Other, Body});
                {error, Error} ->   error(Error);
                Error ->            error(Error)
            end;
        _ ->
            error({"Invalid token type", TokenType})
    end.

sc_verify_sms_token(AppId, To, Token) when is_binary(To) ->
    sc_verify_sms_token(AppId, binary_to_list(To), Token);
sc_verify_sms_token(AppId, To, Token) when is_integer(Token) ->
    sc_verify_sms_token(AppId, To, integer_to_list(Token));
sc_verify_sms_token(AppId, To, Token) when is_binary(Token) ->
    sc_verify_sms_token(AppId, To, binary_to_list(Token));
sc_verify_sms_token(AppId, To, Token) ->
    sc_verify_sms_token( ?GET_CONFIG(smsTokenValidationServiceUrl,[AppId], "https://api.swisscom.com/v1/tokenvalidation")
                       , ?GET_CONFIG(smsTokenValidationClientId,[AppId], "RokAOeF59nkcFg2GtgxgOdZzosQW1MPQ")
                       , To
                       , Token
                       , imem_client:get_profile(httpc, ?HTTP_PROFILE(AppId), ?HTTP_OPTS(AppId))
                       ).

sc_verify_sms_token(Url, ClientId, To, Token, Profile) ->
    case httpc:request( get
                      , { string:join([Url,To,Token],"/")
                        , [ {"client_id",ClientId}
                          , {"Accept","application/json; charset=utf-8"}
                          ]
                        }
                      , [{ssl,[{verify,0}]},{url_encode,false}]
                      , [{full_result, false}]
                      , Profile) of
        {ok,{200,[]}} ->    ok;
        {ok,{400,Body}} ->  error({"HTTP 400", Body});
        {ok,{401,_}} ->     error("HTTP 401: Unauthorized");
        {ok,{403,_}} ->     error("HTTP 403: Client IP not whitelisted");
        {ok,{404,_}} ->     error("HTTP 404: Wrong URL or the given customer not found");
        {ok,{500,Body}} ->  error({"HTTP 500", Body});
        {error, Error} ->   error(Error);
        Error ->            error(Error)
    end.

