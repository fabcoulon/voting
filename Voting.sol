// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

  contract Voting is Ownable {

    uint public _workflowStep;
    uint public _proposalId = 1;
    uint public _numberOfVoters;
    uint[] public _winningProposalsId;
    uint[] public votes;
    uint[] public secondRoundvotes;
    Proposal[] public winners;

    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    event secondRoundVoted (address voter, uint proposalId);

      // regarder les slides du 08/02/2023

      constructor() {
        _voters[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4] = Voter(true,false,0,address(0),false,1);
        _voters[0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2] = Voter(true,false,0,address(0),false,1);
        _voters[0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db] = Voter(true,false,0,address(0),false,1);
        _proposals[0].description = "proposition 1";
        _proposals[0].proposalId = 1;
        _proposals[0].voteCount++;
        votes.push(0);
        
        _proposals[1].description = "proposition 2";
        _proposals[1].proposalId = 2;
        _proposals[1].voteCount++;
        _proposals[1].voteCount++;
        _proposals[1].voteCount++;
        votes.push(1);

        _proposals[2].description = "proposition 2";
        _proposals[2].proposalId = 3;
        _proposals[2].voteCount++;
        _proposals[2].voteCount++;
        _proposals[2].voteCount++;
        votes.push(2);
        _workflowStep = 5;
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

    WorkflowStatus[10] WorkflowSteps = 
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

    mapping(address => Voter) public _voters;
    mapping(uint => address) internal _votersAddress;
    mapping(uint => Proposal) public _proposals;
    mapping(uint => Proposal) public _SecondRoundProposals;

    modifier contractClosed(){
	require(_workflowStep < uint(WorkflowStatus.VotesClosed), "contract closed");
    _;
    }

    function changeWorkflowStatus() external onlyOwner{
        require(_workflowStep < 9, "Last step");

        require(_numberOfVoters > 1,"Quorum of 2 not reached");

        emit WorkflowStatusChange(WorkflowSteps[_workflowStep],WorkflowSteps[_workflowStep+1]);
        _workflowStep++;
    }

    // Gérer l'adresse 0
    function registerVoter(address _address) external onlyOwner contractClosed{
        require(WorkflowSteps[_workflowStep] == WorkflowStatus.RegisteringVoters, "Not registration time !");
        require(!_voters[_address].isRegistered, "Already added !");
        require(_address != address(0), "Incorrect address");
        _voters[_address] = Voter(true,false,0,address(0),false,1);
        _votersAddress[_numberOfVoters] = _address;
        _numberOfVoters++;
        emit VoterRegistered(_address); 
    }

    function ProposalRegistration(string calldata _proposal) external contractClosed{
        require(WorkflowSteps[_workflowStep] == WorkflowStatus.ProposalsRegistrationStarted, "Not proposal registration time !");
        require(_voters[msg.sender].isRegistered, "Not registrated !");
        _proposals[_proposalId].description = _proposal;
        _proposals[_proposalId].proposalId = _proposalId;
        emit ProposalRegistered(_proposalId);
        _proposalId++;
    }

    function Vote(uint _proposalSelectedId) external contractClosed{

        require(WorkflowSteps[_workflowStep] == WorkflowStatus.VotingSessionStarted || WorkflowSteps[_workflowStep] == WorkflowStatus.SecondVotingSessionStarted, "Not voting time !");
        require(_proposalSelectedId > _proposalId, "Proposal not exists");

            if(WorkflowSteps[_workflowStep] == WorkflowStatus.VotingSessionStarted) {
                require(_voters[msg.sender].hasVoted, "Already voted !");
                // set voter data
                _voters[msg.sender].hasVoted = true;
                _voters[msg.sender].votedProposalId = _proposalSelectedId;
                _voters[msg.sender].weight--;
                // set proposal data
                _proposals[_proposalSelectedId].voteCount++;
                // put proposal selected in array of int
                votes.push(_proposalSelectedId); // push selected proposal ids in an array to iterate
                emit Voted (msg.sender, _proposalSelectedId);
            }
            else if(WorkflowSteps[_workflowStep] == WorkflowStatus.SecondVotingSessionStarted) {
                require(_voters[msg.sender].hasSecondRoundVoted, "Already voted !");
                // set voter data
                _voters[msg.sender].hasSecondRoundVoted = true;
                _voters[msg.sender].votedProposalId = _proposalSelectedId;

                // set proposal data
                _SecondRoundProposals[_proposalSelectedId].voteCount++;

                // put proposal selected in array of int
                secondRoundvotes.push(_proposalSelectedId); // push selected proposal ids in an array to iterate

                emit secondRoundVoted (msg.sender, _proposalSelectedId);
            }
        }

    // function getWinner() public onlyOwner view returns (Proposal memory) {
    function getWinner() external onlyOwner returns (uint[] memory) {
        require(WorkflowSteps[_workflowStep] == WorkflowStatus.VotesTallied || WorkflowSteps[_workflowStep] == WorkflowStatus.SecondRoundVotesTallied, "Votes not closed !");

        uint mostVotedProposal = 0;
        uint winningProposalId ;

        if(WorkflowSteps[_workflowStep] == WorkflowStatus.VotesTallied)
        {
            for (uint i = 0; i <votes.length; i++) {
                if(_proposals[votes[i]].voteCount > mostVotedProposal)
                {
                    mostVotedProposal = _proposals[votes[i]].voteCount;
                    winningProposalId = votes[i];
                }
            }
            // mnanage equality
            uint256 frequenceOfMax = 0;
            for (uint256 i = 0; i < votes.length; i++) {
                if (_proposals[votes[i]].voteCount == mostVotedProposal) {
                frequenceOfMax ++;
                _SecondRoundProposals[i].proposalId = _proposals[votes[i]].proposalId;
                _SecondRoundProposals[i].description = _proposals[votes[i]].description;
                _winningProposalsId.push(_proposals[votes[i]].proposalId);
                } 
            }

            if(frequenceOfMax > 1){
                // On change d'étape et on refait le vote
                _workflowStep++;
            }
            else{
                    _workflowStep = 9;
            }
        return (_winningProposalsId);     
        }
        else if(WorkflowSteps[_workflowStep] == WorkflowStatus.SecondRoundVotesTallied) {
            for (uint i = 0; i <secondRoundvotes.length; i++) {
            if(_SecondRoundProposals[secondRoundvotes[i]].voteCount > mostVotedProposal)
            {
                mostVotedProposal = _SecondRoundProposals[secondRoundvotes[i]].voteCount;
                winningProposalId = secondRoundvotes[i];
            }
            }

            // mnanage equality
            uint256 frequenceOfMax = 0;
            for (uint256 i = 0; i < secondRoundvotes.length; i++) {
                if (_SecondRoundProposals[secondRoundvotes[i]].voteCount == mostVotedProposal) {
                frequenceOfMax ++;
                _SecondRoundProposals[i].proposalId = _SecondRoundProposals[secondRoundvotes[i]].proposalId;
                _SecondRoundProposals[i].description = _SecondRoundProposals[secondRoundvotes[i]].description;
                _winningProposalsId.push(_SecondRoundProposals[secondRoundvotes[i]].proposalId);
                } 
            }       

            if(frequenceOfMax > 1){
                for(uint i = 0; i <_numberOfVoters;i++){
                    _voters[_votersAddress[i]].weight = 1;
                }
            }
        }
                return (_winningProposalsId);  
    }

    // function secondRoundVote(uint _proposalSelectedId) public contractClosed{

    //     require(WorkflowSteps[_workflowStep] == WorkflowStatus.SecondVotingSessionStarted, "Not second round !");
    //     require(_voters[msg.sender].isRegistered, "Not registrated !");
    //     require(_voters[msg.sender].hasSecondRoundVoted, "Already voted !");
    //     // set voter data
    //     _voters[msg.sender].hasSecondRoundVoted = true;
    //     _voters[msg.sender].votedProposalId = _proposalSelectedId;

    //     // set proposal data
    //     _SecondRoundProposals[_proposalSelectedId].voteCount++;

    //     // put proposal selected in array of int
    //     secondRoundvotes.push(_proposalSelectedId); // push selected proposal ids in an array to iterate

    //     emit secondRoundVoted (msg.sender, _proposalSelectedId);
    //     }

    // function getsecondRoundWinner() public onlyOwner returns (uint[] memory) {
    //     require(WorkflowSteps[_workflowStep] == WorkflowStatus.SecondRoundVotesTallied, "Second tour votes not closed !");

    //     uint mostVotedProposal = 0;
    //     uint winningProposalId;

    //     for (uint i = 0; i <secondRoundvotes.length; i++) {
    //         if(_SecondRoundProposals[secondRoundvotes[i]].voteCount > mostVotedProposal)
    //         {
    //             mostVotedProposal = _SecondRoundProposals[secondRoundvotes[i]].voteCount;
    //             winningProposalId = secondRoundvotes[i];
    //         }
    //     }

    //     // mnanage equality
    //     uint256 frequenceOfMax = 0;
    //     for (uint256 i = 0; i < secondRoundvotes.length; i++) {
    //         if (_SecondRoundProposals[secondRoundvotes[i]].voteCount == mostVotedProposal) {
    //         frequenceOfMax ++;
    //         _SecondRoundProposals[i].proposalId = _SecondRoundProposals[secondRoundvotes[i]].proposalId;
    //         _SecondRoundProposals[i].description = _SecondRoundProposals[secondRoundvotes[i]].description;
    //         _winningProposalsId.push(_SecondRoundProposals[secondRoundvotes[i]].proposalId);
    //         } 
    //     }       

    //     if(frequenceOfMax > 1){
    //          for(uint i = 0; i <_numberOfVoters;i++){
    //              _voters[_votersAddress[i]].weight = 1;
    //          }
    //     }
    //     return (_winningProposalsId);
    // }

      function delegate( address _to) external {
          Voter memory sender = _voters[msg.sender];
          require(!sender.hasVoted);
          require(_to != msg.sender);
          while (_voters[_to].delegate != address(0)) {
              _to = _voters[_to].delegate;
              require(_to != msg.sender);
          }
          sender.hasVoted = true;
          sender.delegate = _to;
          Voter memory delegateVoter = _voters[_to];
          if (delegateVoter.hasVoted) {
              _proposals[delegateVoter.votedProposalId].voteCount += sender.weight;
          } else {
              delegateVoter.weight += sender.weight;
          }
      }
}