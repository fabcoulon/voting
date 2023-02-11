// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

  contract Voting is Ownable {

    uint private workflowStatus;
    uint public proposalId;
    uint public voterId;
    uint public winningProposalId;
    uint public votes;
    uint public secondRoundVotes;
    uint[] public winningProposalsId;
    uint mostVotedProposal;
    bool isDraw;
    uint frequenceOfMax;

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
    mapping(WorkflowStatus => string) private workflowSteps; // for getter function workFlowStep()

    modifier contractNotClosed(){
	require(workflowStatus < uint(WorkflowStatus.VotesClosed), "contract closed");
    _;
    }

    function changeWorkflowStatus() external onlyOwner{
        require(workflowStatus < uint(WorkflowStatus.VotesClosed), "Last step");
        require(voterId > 1,"Quorum not reached");
        
        if(proposalId < 1 && workflowStatus == uint(WorkflowStatus.ProposalsRegistrationStarted)){ revert("No proposals");}
        else if(votes < 1 && workflowStatus == uint(WorkflowStatus.VotingSessionStarted)){ revert("No voters");}
        else if(secondRoundVotes < 1 && workflowStatus == uint(WorkflowStatus.SecondVotingSessionStarted)){ revert("No voters");}
        else if(winningProposalsId.length < 1 && workflowStatus == uint(WorkflowStatus.VotesTallied)){ revert("No one elected");}
        workflowStatus++;

        emit WorkflowStatusChange(WorkflowSteps[workflowStatus],WorkflowSteps[workflowStatus+1]);
    }

    function registerVoter(address _address) external onlyOwner contractNotClosed {
        require(workflowStatus == uint(WorkflowStatus.RegisteringVoters), "Not registration time !");
        require(!voters[_address].isRegistered, "Already added !");
        require(_address != address(0), "Incorrect address");

        voterId++;
        voters[_address] = Voter(true,false,0,address(0),false,0,1);
        votersAddress[voterId] = _address;

        emit VoterRegistered(_address); 
    }

    function ProposalRegistration(string calldata _proposal) external contractNotClosed{
        require(workflowStatus == uint(WorkflowStatus.ProposalsRegistrationStarted), "Not proposal registration time !");
        require(voters[msg.sender].isRegistered, "Not registrated !");
        require(bytes(_proposal).length > 0,"Not empty message");

        proposalId++;
        proposals[proposalId].description = _proposal;
        emit ProposalRegistered(proposalId);
    }

    function Vote(uint _proposalSelectedId) external contractNotClosed{
        bool VotingSessionStarted = workflowStatus == uint(WorkflowStatus.VotingSessionStarted);
        bool SecondVotingSessionStarted = workflowStatus == uint(WorkflowStatus.SecondVotingSessionStarted);

        require(VotingSessionStarted || SecondVotingSessionStarted, "Not voting time !");
        require(_proposalSelectedId != 0 && _proposalSelectedId <= proposalId, "Proposal not exists");
        require(voters[msg.sender].isRegistered, "Not registrated !");

        if(VotingSessionStarted) {
            voteAtFirstStep(_proposalSelectedId);
        }
        else if(SecondVotingSessionStarted) {
            voteAtSecondStep(_proposalSelectedId);
        }
    } 

    function getWinner() external {
        bool VotesTallied = workflowStatus == uint(WorkflowStatus.VotesTallied);
        bool SecondRoundVotesTallied = workflowStatus == uint(WorkflowStatus.SecondRoundVotesTallied);

        require(VotesTallied || SecondRoundVotesTallied, "Closing steps !");

        if(VotesTallied)
        {       
            getWinnerOfFirstVote();
        }
        else if(SecondRoundVotesTallied) {
            getWinnerOfSecondVote();
        }
    }

    function delegate(address _to) external contractNotClosed{
        require(voters[_to].isRegistered, "Not registrated !");
        require(_to != msg.sender,"No self delegation");

        bool underSecondVotingSessionStarted = workflowStatus < uint(WorkflowStatus.SecondVotingSessionStarted);
        bool overSecondVotingSessionStarted = workflowStatus >= uint(WorkflowStatus.SecondVotingSessionStarted);
        
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

        if(underSecondVotingSessionStarted){firstRoundDelegate(sender,delegateVoter);}
        else if(overSecondVotingSessionStarted){secondRoundDelegate(sender,delegateVoter);}

        sender.weight--;
        emit delegated(msg.sender,_to); 
    }

    function voteAtFirstStep(uint _proposalSelectedId) private{
        require(!voters[msg.sender].hasVoted, "Already voted");

        // In case of delegation
        if(voters[msg.sender].weight == 1)
        {      
            voters[msg.sender].hasVoted = true;
        }    

        voters[msg.sender].votedProposalId = _proposalSelectedId;     
        voters[msg.sender].weight--;           
        proposals[_proposalSelectedId].voteCount++;
        votes++;

        emit Voted (msg.sender, _proposalSelectedId);       
    }

    function voteAtSecondStep(uint _proposalSelectedId) private{
        require(!voters[msg.sender].hasSecondRoundVoted, "Already voted");

        // In case of delegation
        if(voters[msg.sender].weight == 1)
        {      
            voters[msg.sender].hasSecondRoundVoted = true;
        }
        
        voters[msg.sender].secondRoundProposalId = _proposalSelectedId;   
        voters[msg.sender].weight--;          
        secondRoundProposals[_proposalSelectedId].voteCount++;
        secondRoundVotes++;

        emit secondRoundVoted (msg.sender, _proposalSelectedId);
    } 

    function getWinnerOfFirstVote() private{

        mostVotedProposal = getMostVotedProposal(proposals);
        frequenceOfMax = checkDraw(proposals);
        isDraw = frequenceOfMax > 1;            
        
        if(!isDraw){
            // No second round
            winningProposalId = winningProposalsId[0];
            workflowStatus = uint(WorkflowStatus.VotesClosed);
        }
        else{
            // second round
            workflowStatus++;
            mostVotedProposal = 0;
            proposalId = frequenceOfMax;
            // Give weight to voters for the second round
            for(uint i = 0; i <voterId;i++){
                voters[votersAddress[i]].weight = 1;
            }
        }  
    }

    function getWinnerOfSecondVote() private{
        mostVotedProposal = getMostVotedProposal(secondRoundProposals);
        // If draw after second round. No winners
        frequenceOfMax = checkDraw(secondRoundProposals);
        isDraw = frequenceOfMax > 1; 
        if(!isDraw){
            winningProposalId = winningProposalsId[0];
        }
        workflowStatus = uint(WorkflowStatus.VotesClosed);    
    }

        function getMostVotedProposal(mapping(uint => Proposal) storage _proposals) private returns (uint){
        mostVotedProposal = 0;

         for (uint i = 0; i <voterId; i++) {
                if(_proposals[i].voteCount > mostVotedProposal)
                {
                    mostVotedProposal = _proposals[i].voteCount;
                }
        }
        return mostVotedProposal;
    }

    function checkDraw(mapping(uint => Proposal) storage _proposals) private returns(uint){
        frequenceOfMax = 0;

        delete winningProposalsId; 

        uint j = 0; //id of the secondRoundProposals
        for (uint i = 0; i < proposalId+1; i++) {
            if (_proposals[i].voteCount == mostVotedProposal) {
            j++;
            frequenceOfMax ++;
            secondRoundProposals[j].description = _proposals[i].description;
            winningProposalsId.push(i);
            }
        }
        return frequenceOfMax;
    }

    function firstRoundDelegate(Voter storage _sender, Voter storage _delegateVoter) private {
        _sender.hasVoted = true;
        if (_delegateVoter.hasVoted) {
            _delegateVoter.hasVoted = false;
            _sender.votedProposalId = _delegateVoter.votedProposalId;
        } else {
            _sender.votedProposalId = 1;
        }
    }

    function secondRoundDelegate(Voter storage _sender, Voter storage _delegateVoter) private{
          _sender.hasVoted = true;
            if (_delegateVoter.hasSecondRoundVoted) {
                _delegateVoter.hasSecondRoundVoted = false;
                _sender.secondRoundProposalId = _delegateVoter.secondRoundProposalId;
            } else {
                _sender.secondRoundProposalId = 1;
            }
    }

    function workFlowStep() external view returns (string memory) {
        return workflowSteps[WorkflowSteps[workflowStatus]];
    }
}