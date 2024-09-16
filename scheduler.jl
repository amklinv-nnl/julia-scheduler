##
using Gurobi, JuMP, YAML 
using OrderedCollections
## Read the input from a yaml file
mini = YAML.load_file("genetic_scheduling/data/SIAM-MDS24/minisymposia.yaml", dicttype=OrderedDict)

##
nrooms = 11
nslots = 10 
nmini = length(mini)
room_capacities=nrooms:-1:1
##
sim = zeros(nmini, nmini)
for (i, ms) ∈ enumerate(keys(mini)), (j, ms2) ∈ enumerate(keys(mini))
    for c1 ∈ mini[ms]["class codes"]
        if c1 ∈ mini[ms2]["class codes"]
            sim[i,j] += 1
        end
    end
end
##
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
##
m = Model(Gurobi.Optimizer)
@variable(m, assignments[1:nmini,1:nrooms,1:nslots], Bin)
@variable(m, sametime[1:nmini,1:nmini,1:nslots], Bin)
@variable(m, conflict[1:nmini,1:nmini], Bin)
# All minisymposia must be scheduled
for i in 1:nmini
  @constraint(m, sum(assignments[i,:,:]) == 1)
end
# Each room can only be used once in the same timeslot
for i in 1:nrooms, j in 1:nslots
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
# Setup the same time matrix
for i in 1:nmini, j in 1:nmini, t in 1:nslots
  @constraint(m, sametime[i,j,t] >= sum(assignments[i,:,t]) + sum(assignments[j,:,t]) - 1)
  @constraint(m, sametime[i,j,t] <= sum(assignments[i,:,t]))
  @constraint(m, sametime[i,j,t] <= sum(assignments[j,:,t]))
end
# setup the conflict matrix
for i in 1:nmini, j in 1:nmini
  @constraint(m, conflict[i,j] == sum(sametime[i,j,:]))
end

@objective(m, Min, sum([sim[m,m2]*conflict[m,m2] for m in 1:nmini, m2 in 1:nmini]))

JuMP.optimize!(m)
