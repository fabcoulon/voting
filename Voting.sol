// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

  contract Voting is Ownable {

    uint private workflowStep;
    uint public proposalId;
    uint public voterId;
    uint public winningProposalId;
    uint public votes;
    uint public secondRoundVotes;
    uint[] public winningProposalsId;

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
    uint secondRoundProposalId;
    uint weight;
    }

    struct Proposal {
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
    mapping(uint => address) public votersAddress; // Used to reload weight;
    mapping(uint => Proposal) public proposals;
    mapping(uint => Proposal) public secondRoundProposals;
    mapping(WorkflowStatus => string) private workflowSteps;

    modifier contractNotClosed(){
	require(workflowStep < uint(WorkflowStatus.VotesClosed), "contract closed");
    _;
    }

    function changeWorkflowStatus() external onlyOwner{
        require(WorkflowSteps[workflowStep] < WorkflowStatus.VotesClosed, "Last step");
        require(voterId > 1,"Quorum not reached");
        emit WorkflowStatusChange(WorkflowSteps[workflowStep],WorkflowSteps[workflowStep+1]);
        
        if(proposalId < 1 && WorkflowSteps[workflowStep] == WorkflowStatus.ProposalsRegistrationStarted){ revert("No proposals");}
        else if(votes < 1 && WorkflowSteps[workflowStep] == WorkflowStatus.VotingSessionStarted){ revert("No voters");}
        else if(secondRoundVotes < 1 && WorkflowSteps[workflowStep] == WorkflowStatus.SecondVotingSessionStarted){ revert("No voters");}
        else if(winningProposalsId.length < 1 && WorkflowSteps[workflowStep] == WorkflowStatus.VotesTallied){ revert("No one elected");}
        workflowStep++;
    }

    function registerVoter(address _address) external onlyOwner contractNotClosed {
        require(WorkflowSteps[workflowStep] == WorkflowStatus.RegisteringVoters, "Not registration time !");
        require(!voters[_address].isRegistered, "Already added !");
        require(_address != address(0), "Incorrect address");

        voterId++;
        voters[_address] = Voter(true,false,0,address(0),false,0,1);
        votersAddress[voterId] = _address;

        emit VoterRegistered(_address); 
    }

    function ProposalRegistration(string calldata _proposal) external contractNotClosed{
        require(WorkflowSteps[workflowStep] == WorkflowStatus.ProposalsRegistrationStarted, "Not proposal registration time !");
        require(voters[msg.sender].isRegistered, "Not registrated !");
        require(bytes(_proposal).length > 0,"Not empty message");

        // set proposal id and description
        proposals[proposalId].description = _proposal;
        proposalId++;

        emit ProposalRegistered(proposalId);
    }

    function Vote(uint _proposalSelectedId) external contractNotClosed{
        bool VotingSessionStarted = WorkflowSteps[workflowStep] == WorkflowStatus.VotingSessionStarted;
        bool SecondVotingSessionStarted = WorkflowSteps[workflowStep] == WorkflowStatus.SecondVotingSessionStarted;

        require(VotingSessionStarted || SecondVotingSessionStarted, "Not voting time !");
        require(_proposalSelectedId != 0 && _proposalSelectedId <= proposalId, "Proposal not exists");
        require(voters[msg.sender].isRegistered, "Not registrated !");

        if(VotingSessionStarted) {
            require(!voters[msg.sender].hasVoted, "Already voted");
            voteAtStep(_proposalSelectedId,proposals,true);
            votes++;
        }
        else if(SecondVotingSessionStarted) {
            require(!voters[msg.sender].hasSecondRoundVoted, "Already voted");
            voteAtStep(_proposalSelectedId,secondRoundProposals,false);
            secondRoundVotes++;
        }
    }

    function getWinner() external {
        bool VotesTallied = WorkflowSteps[workflowStep] == WorkflowStatus.VotesTallied;
        bool SecondRoundVotesTallied = WorkflowSteps[workflowStep] == WorkflowStatus.SecondRoundVotesTallied;

        require(VotesTallied || SecondRoundVotesTallied, "Closing steps !");

        uint mostVotedProposal;
        bool isDraw;
        uint frequenceOfMax;

        if(VotesTallied)
        {       
            mostVotedProposal = getMostVotedProposal(proposals);
            frequenceOfMax = checkDraw(mostVotedProposal, proposals);
            isDraw = frequenceOfMax > 1;            
            
            if(!isDraw){
                // No second round
                winningProposalId = winningProposalsId[0];
                workflowStep = uint(WorkflowStatus.VotesClosed);
            }
            else{
                 // second round
                workflowStep++;
                mostVotedProposal = 0;
                proposalId = frequenceOfMax;
                // Give weight to voters for the second round
                for(uint i = 0; i <voterId+1;i++){
                    voters[votersAddress[i]].weight = 1;
                }
            }  
        }
        else if(SecondRoundVotesTallied) {

            mostVotedProposal = getMostVotedProposal(secondRoundProposals);
            // If draw after second round. No winners
            frequenceOfMax = checkDraw(mostVotedProposal, secondRoundProposals);
            isDraw = frequenceOfMax > 1; 
            if(!isDraw){
                 winningProposalId = winningProposalsId[0];
            }
            workflowStep = uint(WorkflowStatus.VotesClosed);    
        }
    }

    function delegate(address _to) external contractNotClosed{
        require(voters[_to].isRegistered, "Not registrated !");
        require(_to != msg.sender,"No self delegation");

        bool underSecondVotingSessionStarted = WorkflowSteps[workflowStep] < WorkflowStatus.SecondVotingSessionStarted;
        bool overSecondVotingSessionStarted = WorkflowSteps[workflowStep] >= WorkflowStatus.SecondVotingSessionStarted;
        
        Voter storage sender = voters[msg.sender];
        Voter storage delegateVoter = voters[_to];

        if(underSecondVotingSessionStarted){ require(!sender.hasVoted,"Already voted");}
        else if(overSecondVotingSessionStarted){ require(!sender.hasSecondRoundVoted,"Already voted");}

        while (voters[_to].delegate != address(0)) {
            _to = voters[_to].delegate;
            require(_to != msg.sender);
        }
        sender.delegate = _to;

        delegateVoter.weight ++;

        if(underSecondVotingSessionStarted)
            {
            sender.hasVoted = true;
            if (delegateVoter.hasVoted) {
                delegateVoter.hasVoted = false;
                sender.votedProposalId = delegateVoter.votedProposalId;
            } else {
                sender.votedProposalId = 1;
            }
        }
        else if(overSecondVotingSessionStarted)
        {
             sender.hasVoted = true;
            if (delegateVoter.hasSecondRoundVoted) {
                delegateVoter.hasSecondRoundVoted = false;
                sender.secondRoundProposalId = delegateVoter.secondRoundProposalId;
            } else {
                sender.secondRoundProposalId = 1;
            }
        }
        sender.weight--;
        emit delegated(msg.sender,_to); 
    }

    function getMostVotedProposal(mapping(uint => Proposal) storage _proposals) private view returns (uint){
        uint mostVotedProposal = 0;

         for (uint i = 0; i <voterId; i++) {
                if(_proposals[i].voteCount > mostVotedProposal)
                {
                    mostVotedProposal = _proposals[i].voteCount;
                }
        }
        return mostVotedProposal;
    }

    function checkDraw(uint _mostVotedProposal, mapping(uint => Proposal) storage _proposals) private returns(uint){
        uint256 frequenceOfMax = 0;

        delete winningProposalsId; 

        for (uint i = 0; i < voterId; i++) {

            if (_proposals[i].voteCount == _mostVotedProposal) {
            frequenceOfMax ++;
            secondRoundProposals[i].description = _proposals[i].description;
            winningProposalsId.push(i);
            } 
        }
        return frequenceOfMax;
    }

    function voteAtStep(uint _proposalSelectedId, mapping(uint => Proposal) storage _proposals, bool firstRound) private {

        // In case of delegation
        if(voters[msg.sender].weight == 1)
        {      
            firstRound
            ?       voters[msg.sender].hasVoted = true
            :       voters[msg.sender].hasSecondRoundVoted = true;
        }
        
         firstRound
            ?       voters[msg.sender].votedProposalId = _proposalSelectedId
            :       voters[msg.sender].secondRoundProposalId = _proposalSelectedId;
      
        voters[msg.sender].weight--;
            
        _proposals[_proposalSelectedId].voteCount++;

        if(firstRound) { emit Voted (msg.sender, _proposalSelectedId); } else { emit secondRoundVoted (msg.sender, _proposalSelectedId); } 
    }

    function workFlowStep() external view returns (string memory) {
        return workflowSteps[WorkflowSteps[workflowStep]];
    }
}