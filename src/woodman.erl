-module(woodman).

-export([
         get_utilization_stats/1,
         get_full_tree_stats/1
        ]).

-export([
         update_tree/1,
         traverse/1
        ]).

get_utilization_stats(SupervisorName) ->
    [_ | T] = traverse({SupervisorName, regname(SupervisorName), supervisor}),
    update_tree(T).

get_full_tree_stats(R) ->
    T = traverse({R, regname(R), supervisor}),
    [_UaSup | Supervisors] = lists:flatten(T),
    [{SupName, erlang:process_info(Pid, [message_queue_len, memory])} 
     || {Pid, SupName, _Type} <- Supervisors].

regname(R) ->
    try {registered_name, N} = process_info(R, registered_name), N
    catch _:_ -> undefined
                 end.

traverse({N = undefined, Id, T})  -> {N, Id, T};
traverse({N, Id, T = worker})     -> {N, Id, T};
traverse({N, Id, T = supervisor}) ->
    Cs = supervisor:which_children(N),
    [{N, Id, T} |  [traverse({CN, CId, CT}) || {CId, CN, CT, _CMs} <- Cs]].

update_tree(Tree) ->
    lists:map(fun update_child/1, Tree).

update_child(Child) when is_list(Child) ->
    update_supervisor(Child);
update_child({Pid, Name, worker}) -> 
    {Name, erlang:process_info(Pid, [message_queue_len, memory])};
update_child({Pid, Name, supervisor}) -> 
    {Name, erlang:process_info(Pid, [message_queue_len, memory])}.

update_supervisor([{Pid, Name, supervisor} | []]) ->
    {Name, erlang:process_info(Pid, [message_queue_len, memory])};
update_supervisor([{Pid, Name, supervisor} | Childs]) ->
    T1 = update_tree(Childs),
    ChildsMsgQueueLen = lists:foldl(fun({_, Stats}, Acc) -> 
                                              Acc + proplists:get_value(message_queue_len, Stats, 0) end, 0, T1),
    ChildsMemoryUsage = lists:foldl(fun({_, Stats}, Acc) -> 
                                              Acc + proplists:get_value(memory, Stats, 0) end, 0, T1),
    SupStats = erlang:process_info(Pid, [message_queue_len, memory]),
    SupMemory = proplists:get_value(memory, SupStats, 0),
    SupQueueLen = proplists:get_value(message_queue_len, SupStats, 0),
    {Name, [{memory, SupMemory+ChildsMemoryUsage}, 
            {message_queue_len, SupQueueLen+ChildsMsgQueueLen}]}.
