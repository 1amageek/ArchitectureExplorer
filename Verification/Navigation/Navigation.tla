---------------------- MODULE Navigation ----------------------
EXTENDS Naturals, FiniteSets
CONSTANT PermitStale
VARIABLES generation, phase, committed, started, pending, displayed
vars == <<generation, phase, committed, started, pending, displayed>>
Init == /\ generation = 0 /\ phase = "ready"
        /\ committed = {} /\ started = {} /\ pending = {} /\ displayed = 0
Open == /\ generation < 3
        /\ generation' = generation + 1 /\ phase' = "loading"
        /\ committed' = committed \cup {generation + 1}
        /\ displayed' = 0 /\ UNCHANGED <<started, pending>>
Start == /\ phase = "loading" /\ generation \notin started
         /\ started' = started \cup {generation}
         /\ pending' = pending \cup {generation}
         /\ UNCHANGED <<generation, phase, committed, displayed>>
Reply(id, result) == /\ id \in pending
                     /\ pending' = pending \ {id}
                     /\ IF id = generation \/ PermitStale
                         THEN /\ phase' = result /\ displayed' = id
                         ELSE UNCHANGED <<phase, displayed>>
                     /\ UNCHANGED <<generation, committed, started>>
Back == /\ generation < 3
        /\ generation' = generation + 1 /\ phase' = "ready" /\ displayed' = 0
        /\ UNCHANGED <<committed, started, pending>>
Next == Open \/ Start \/ Back \/ (\E id \in pending, result \in {"ready", "failed"}: Reply(id, result))
Spec == Init /\ [][Next]_vars
DestinationBeforeRead == started \subseteq committed
CurrentResultOnly == displayed = 0 \/ displayed = generation
NoOldResultWhileLoading == phase = "loading" => displayed = 0
===============================================================
