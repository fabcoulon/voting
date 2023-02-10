// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

  contract Voting is Ownable {

    uint private workflowStep;
    uint public proposalId;
    uint public numberOfVoters;
    uint[] public winningProposalsId;
    uint public winningProposalId;
    uint[] public votes;
    uint[] public secondRoundvotes;

    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    event secondRoundVoted (address voter, uint proposalId);
    event delegated(address from,address to);

      constructor() {
            workflowSteps[WorkflowStatus.RegisteringVoters] = "Registering voters";
            workflowSteps[WorkflowStatus.ProposalsRegistrationStarted] = "Proposals registration started";
            workflowSteps[WorkflowStatus.ProposalsRegistrationEnded] = "proposals registration ended";
            workflowSteps[WorkflowStatus.VotingSessionStarted] = "Voting session started";
            workflowSteps[WorkflowStatus.VotingSessionEnded] = "Voting session ended";
            workflowSteps[WorkflowStatus.VotesTallied] = "Votes tallied";
            workflowSteps[WorkflowStatus.SecondVotingSessionStarted] = "Second voting session started";
            workflowSteps[WorkflowStatus.SecondVotingSessionEnded] = "Second voting session ended";
            workflowSteps[WorkflowStatus.SecondRoundVotesTallied] = "Second round votes tallied";
            workflowSteps[WorkflowStatus.VotesClosed] = "Votes closed";
      }

    enum WorkflowStatus {
    RegisteringVoters,
    ProposalsRegistrationStarted,
    ProposalsRegistrationEnded,
    VotingSessionStarted,
    VotingSessionEnded,
    VotesTallied,
    SecondVotingSessionStarted,
    SecondVotingSessionEnded,
    SecondRoundVotesTallied,
    VotesClosed
    }

    struct Voter {
    bool isRegistered;
    bool hasVoted;
    uint votedProposalId;
    address delegate;
    bool hasSecondRoundVoted;
    uint weight;
    }

    struct Proposal {
    uint proposalId;
    string description;
    uint voteCount;
    }

    WorkflowStatus[10] private WorkflowSteps = 
    [WorkflowStatus.RegisteringVoters,
    WorkflowStatus.ProposalsRegistrationStarted,
    WorkflowStatus.ProposalsRegistrationEnded,
    WorkflowStatus.VotingSessionStarted,
    WorkflowStatus.VotingSessionEnded,
    WorkflowStatus.VotesTallied,
    WorkflowStatus.SecondVotingSessionStarted,
    WorkflowStatus.SecondVotingSessionEnded,
    WorkflowStatus.SecondRoundVotesTallied,
    WorkflowStatus.VotesClosed];

    mapping(address => Voter) public voters;
    mapping(uint => address) internal votersAddress;
    mapping(uint => Proposal) public proposals;
    mapping(uint => Proposal) public secondRoundProposals;
    mapping(WorkflowStatus => string) private workflowSteps;

    modifier contractNotClosed(){
	require(workflowStep < uint(WorkflowStatus.VotesClosed), "contract closed");
    _;
    }

    function changeWorkflowStatus() external onlyOwner{
        require(WorkflowSteps[workflowStep] < WorkflowStatus.VotesClosed, "Last step");
        require(numberOfVoters > 1,"Quorum not reached");
        emit WorkflowStatusChange(WorkflowSteps[workflowStep],WorkflowSteps[workflowStep+1]);
        workflowStep++;
    }

    function registerVoter(address _address) external onlyOwner contractNotClosed{
        require(WorkflowSteps[workflowStep] == WorkflowStatus.RegisteringVoters, "Not registration time !");
        require(!voters[_address].isRegistered, "Already added !");
        require(_address != address(0), "Incorrect address");

        voters[_address] = Voter(true,false,0,address(0),false,1);
        numberOfVoters++;
        votersAddress[numberOfVoters] = _address;
        emit VoterRegistered(_address); 
    }

    function ProposalRegistration(string calldata _proposal) external contractNotClosed{
        require(WorkflowSteps[workflowStep] == WorkflowStatus.ProposalsRegistrationStarted, "Not proposal registration time !");
        require(voters[msg.sender].isRegistered, "Not registrated !");
        require(bytes(_proposal).length > 0,"Not empty message");

        proposals[proposalId].description = _proposal;
        proposals[proposalId].proposalId = proposalId;
        emit ProposalRegistered(proposalId);
        proposalId++;
    }

    function Vote(uint _proposalSelectedId) external contractNotClosed{

        require(WorkflowSteps[workflowStep] == WorkflowStatus.VotingSessionStarted || WorkflowSteps[workflowStep] == WorkflowStatus.SecondVotingSessionStarted, "Not voting time !");
        require(_proposalSelectedId < proposalId, "Proposal not exists");

            if(WorkflowSteps[workflowStep] == WorkflowStatus.VotingSessionStarted) {
                require(!voters[msg.sender].hasVoted, "Already voted");
                voteAtStep(_proposalSelectedId,proposals,votes,true);
            }
            else if(WorkflowSteps[workflowStep] == WorkflowStatus.SecondVotingSessionStarted) {
                require(!voters[msg.sender].hasSecondRoundVoted, "Already voted");
                voteAtStep(_proposalSelectedId,secondRoundProposals,secondRoundvotes,false);
            }
        }

    function getWinner() external onlyOwner {
        require(WorkflowSteps[workflowStep] == WorkflowStatus.VotesTallied || WorkflowSteps[workflowStep] == WorkflowStatus.SecondRoundVotesTallied, "Closing steps !");

        uint mostVotedProposal;
        bool isDraw;

        if(WorkflowSteps[workflowStep] == WorkflowStatus.VotesTallied)
        {       
            mostVotedProposal = getMostVotedProposal(proposals,votes);
            isDraw = checkDraw(mostVotedProposal, proposals, votes);

            if(isDraw){
                // second round
                workflowStep++;
                mostVotedProposal = 0;
                // Give rights to voters for the second round
                for(uint i = 0; i <numberOfVoters;i++){
                    voters[votersAddress[i]].weight = 1;
                }
            }
            else{
                // No second round
                winningProposalId = winningProposalsId[0]; 
                workflowStep = uint(WorkflowStatus.VotesClosed);
            }  
        }
        else if(WorkflowSteps[workflowStep] == WorkflowStatus.SecondRoundVotesTallied) {

            mostVotedProposal = getMostVotedProposal(secondRoundProposals,secondRoundvotes);
            // If draw after second round. No winners
            isDraw = checkDraw(mostVotedProposal, secondRoundProposals, secondRoundvotes);
            if(!isDraw){
                 workflowStep = uint(WorkflowStatus.VotesClosed);
                 winningProposalId = winningProposalsId[0];
            }    
        }
    }

    function delegate(address _to) external contractNotClosed{
          Voter storage sender = voters[msg.sender];
          require(!sender.hasVoted,"Already voted");
          require(_to != msg.sender,"No self delegation");
          while (voters[_to].delegate != address(0)) {
              _to = voters[_to].delegate;
              require(_to != msg.sender);
          }
          sender.hasVoted = true;
          sender.delegate = _to;

          Voter storage delegateVoter = voters[_to];
          if (delegateVoter.hasVoted) {
            delegateVoter.hasVoted = false;
          } else {
              delegateVoter.weight ++;
          }
          sender.weight--;
          emit delegated(msg.sender,_to); 
      }

    function getMostVotedProposal(mapping(uint => Proposal) storage _proposals, uint[] memory _votes) private view returns (uint){
        uint mostVotedProposal = 0;

         for (uint i = 0; i <_votes.length; i++) {
                if(_proposals[_votes[i]].voteCount > mostVotedProposal)
                {
                    mostVotedProposal = _proposals[_votes[i]].voteCount;
                }
        }
        return mostVotedProposal;
    }

    function checkDraw(uint _mostVotedProposal, mapping(uint => Proposal) storage _proposals, uint[] memory _votes) private returns(bool){
        uint256 frequenceOfMax = 0;
        for (uint256 i = 0; i < _votes.length; i++) {
            if (_proposals[_votes[i]].voteCount == _mostVotedProposal) {
            frequenceOfMax ++;
            secondRoundProposals[i].proposalId = _proposals[_votes[i]].proposalId;
            secondRoundProposals[i].description = _proposals[_votes[i]].description;
            winningProposalsId.push(_proposals[_votes[i]].proposalId);
            } 
        }
        return frequenceOfMax > 1;
    }

    function voteAtStep(uint _proposalSelectedId, mapping(uint => Proposal) storage _proposals, uint[] storage _votes,bool firstRound) private {

        // In case of delegation
        if(voters[msg.sender].weight == 1)
        {      
            firstRound
            ?       voters[msg.sender].hasVoted = true
            :       voters[msg.sender].hasSecondRoundVoted = true;
        }

        voters[msg.sender].votedProposalId = _proposalSelectedId;
        voters[msg.sender].weight--;

        // If not already in array
        if(_proposals[_proposalSelectedId].voteCount < 1)
            {
            _votes.push(_proposalSelectedId);
            }
            
        // set proposal data
        _proposals[_proposalSelectedId].voteCount++;

        if(firstRound) {
            emit Voted (msg.sender, _proposalSelectedId);
        }
        else
        {
            emit secondRoundVoted (msg.sender, _proposalSelectedId);
        }
    }

    function workFlowStep() external view returns (string memory) {
        return workflowSteps[WorkflowSteps[workflowStep]];
    }
}