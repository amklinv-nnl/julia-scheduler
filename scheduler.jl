using JuMP
using GLPK
import YAML

# Read the input from a yaml file
mini = YAML.load_file("C:/Users/aklin/OneDrive/Documents/GitHub/amklinv/julia-scheduler/mini.yaml", dicttype=OrderedDict)

nrooms = 11
nslots = 10
nmini = length(mini)
room_capacities=nrooms:-1:1

# Compute similarity scores for minisymposia
sim = zeros(nmini, nmini)
for (i, ms) ∈ enumerate(keys(mini)), (j, ms2) ∈ enumerate(keys(mini))
    for c1 ∈ mini[ms]["class codes"]
        if c1 ∈ mini[ms2]["class codes"]
            sim[i,j] += 1
        end
    end
end

function compute_topic_penalty(sim, assignments)
    penalty = 0
    for slot in 1:nslots
        for m in 1:nmini, m2 in 1:nmini
            if sum(assignments[m,:,slot]) ⩓ sum(assignments[m2,:,slot])
                penalty += sim[m,m2]
            end
        end
    end
    return penalty
end

m = Model(GLPK.Optimizer)

@variable(m, assignments[1:nmini,1:nrooms,1:nslots], Bin)

# All minisymposia must be scheduled
for i=1:nmini
    @constraint(m, sum(assignments[i,:,:]) == 1)
end

# Each room can only be used once in the same timeslot
for i=1:nrooms, j=1:nslots
    @constraint(m, sum(assignments[:,i,j]) <= 1)
end

# Enforce prerequisites
for (i, ms) ∈ enumerate(keys(mini))
    if haskey(mini[ms], "prereq")
        for (j, ms2) ∈ enumerate(keys(mini))
            if ms2 == mini[ms]["prereq"]
                print(ms, " has a prerequisite of ", mini[ms]["prereq"], "; ", i, " must come after ", j, "\n")
                @constraint(m, sum([s*sum(assignments[j,:,s]) for s in 1:nslots]) + 1 <= sum([s*sum(assignments[i,:,s]) for s in 1:nslots]))
                break
            end
        end
    end
end

# Enforce speaker availability constraints
for (i, ms) ∈ enumerate(keys(mini))
    if haskey(mini[ms], "available-slots")
        print(ms, "(", i, ") is only available during the timeslots ", mini[ms]["available-slots"], "\n")
        for s ∈ 1:nslots
            if s ∉ mini[ms]["available-slots"]
                @constraint(m, sum(assignments[i,:,s]) == 0)
            end
        end
    end
end

# Don't oversubscribe a given speaker/organizer
for (i, ms) ∈ enumerate(keys(mini)), (j, ms2) ∈ enumerate(keys(mini)), email ∈ mini[ms]["emails"]
    if j <= i
        continue
    end
    if email ∈ mini[ms2]["emails"]
        print(i, " and ", j, " cannot occur at the same time due to ", email, "\n")
        for s=1:nslots
            @constraint(m, sum(assignments[i,:,s]) + sum(assignments[j,:,s]) <= 1)
        end
    end
end

# Minimize the topic conflicts
#@objective(m, Min, sum([sim[m,m2]*sum(assignments[m,:,s])*sum(assignments[m2,:,s]) for s in 1:nslots, m in 1:nmini, m2 in 1:nmini]))

# Maximize the capacity
@objective(m, Max, sum([room_capacities[r]*sum(assignments[:,r,:]) for r in 1:nrooms]))

# Solving the optimization problem
JuMP.optimize!(m)

# Record result
ass = JuMP.value.(assignments)

for i=1:nmini, j=1:nrooms, k=1:nslots
    if ass[i,j,k] > 0
        print(i, " is assigned to room ", j, " in slot ", k, "\n")
    end
end
