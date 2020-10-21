pragma experimental ABIEncoderV2;

contract IDMO is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     
        uint256 rewardDebt; 
		uint256 lock_expire; 
		uint256 lock_amount; 
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           
		uint256 amount;           
        uint256 allocPoint;       
        uint256 lastRewardBlock;  
        uint256 accPerShare; 
    }
	
	struct TokenParam{
		address myTokenAddr;   	
		address devAddr; 	   	
		uint amount1st;  		
		uint blkNum1st;  		
		uint amount2nd;  		
		uint blkNum2nd;  		
		uint amount3rd;  		
		uint blkNum3rd;  		
		uint feeRate;    		
		uint blkNumPriMine; 
	}	
	 
	mapping (uint256 => mapping(uint256 => PoolInfo)) public poolInfo;
	
	mapping (uint256 => mapping(uint256 => mapping (address => UserInfo))) public userInfo; 
	
	 
	mapping(uint256=>uint256) public totalAllocPoint;
	
	 
	mapping(uint256=>uint256) public startBlock; 
	
	uint256 public tokenIndex; 
	
	 
	mapping(uint256=>TokenParam) public tokenInfo; 
	
	mapping(uint256=>uint256) public poolNum;   

	address public delegateContract;  
	
	mapping(address=>uint256) public mapTokenExist;
	
	event Deposit(address indexed user, uint256 indexed tokenid, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed tokenid, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed tokenid, uint256 indexed pid, uint256 amount);
	
	modifier onlyControl(){ 
		address contractOwner = owner();
		require((msg.sender == contractOwner || msg.sender == delegateContract), "Caller error.");
		_;
	}
	modifier onlyDelegate(){ 
		require(msg.sender == delegateContract, "caller error");
		_;
	}
	
	
	function setDelegateContract(address _addr) public onlyOwner{
		
		delegateContract = _addr;
	}
	
	function isTokenExist(address tokenAddr) public  view{
		require(mapTokenExist[tokenAddr] == 0, "token exists");
	}
	
	
	
	function checkTokenParam(TokenParam memory tokenParam) public  view{
		require(tokenParam.myTokenAddr != address(0), "myTokenAddr error");
		isTokenExist(tokenParam.myTokenAddr);
		require(tokenParam.devAddr != address(0), "devAddr error");
		require(((tokenParam.amount1st>0 && tokenParam.blkNum1st>=10000) || (tokenParam.amount1st==0 && tokenParam.blkNum1st==0)), "amount1st blkNum1st error");
		require(((tokenParam.amount2nd>0 && tokenParam.blkNum2nd>=10000) || (tokenParam.amount2nd==0 && tokenParam.blkNum2nd==0)), "amount2nd blkNum2nd error");
		require(((tokenParam.amount3rd>0 && tokenParam.blkNum3rd>=10000) || (tokenParam.amount3rd==0 && tokenParam.blkNum3rd==0)), "amount3rd blkNum3rd error");
		require((tokenParam.feeRate>0 && tokenParam.feeRate<=20), "feeRate error");
		require(tokenParam.blkNumPriMine >= 10000, "blkNumPriMine error");
	}
	
	
	constructor(TokenParam memory tokenParam) public {
        checkTokenParam(tokenParam);
		tokenInfo[tokenIndex] = tokenParam;
		tokenIndex = tokenIndex + 1;
		mapTokenExist[tokenParam.myTokenAddr] = 1;
    }

	function addToken(TokenParam memory tokenParam) public onlyControl returns(uint256){
		checkTokenParam(tokenParam);
		tokenInfo[tokenIndex] = tokenParam;
		uint tokenId = tokenIndex;
		tokenIndex = tokenIndex + 1;
		mapTokenExist[tokenParam.myTokenAddr] = 1;
		return tokenId;
	}
	

	function setStartBlock(uint tokenId, uint _startBlk) public onlyControl{
		require(tokenId < tokenIndex);
		require(startBlock[tokenId] == 0);
		require(_startBlk > block.number);
		startBlock[tokenId] = _startBlk;

		uint256 length = poolNum[tokenId];
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[tokenId][pid].lastRewardBlock = _startBlk;
        }
	}
	

	function poolLength(uint tokenId) external view returns (uint256) {
        return poolNum[tokenId];
    }


	function addPool(uint tokenId, uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyControl {
        if (_withUpdate) {
            massUpdatePools(tokenId);
        }
        uint256 lastRewardBlock = block.number > startBlock[tokenId] ? block.number : startBlock[tokenId];
        totalAllocPoint[tokenId] = totalAllocPoint[tokenId].add(_allocPoint);
        poolInfo[tokenId][poolNum[tokenId]] = PoolInfo({
            lpToken: _lpToken,
			amount: 0,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accPerShare: 0
        });
		poolNum[tokenId] = poolNum[tokenId].add(1);
    }
	

	function setPool(uint tokenId, uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyControl {
        if (_withUpdate) {
            massUpdatePools(tokenId);
        }
        totalAllocPoint[tokenId] = totalAllocPoint[tokenId].sub(poolInfo[tokenId][_pid].allocPoint).add(_allocPoint);
        poolInfo[tokenId][_pid].allocPoint = _allocPoint;
    }
	

	function pendingToken(uint tokenId, uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[tokenId][_pid];
        UserInfo storage user = userInfo[tokenId][_pid][_user];
        uint256 accPerShare = pool.accPerShare;
		if(startBlock[tokenId] == 0){
			return 0;
		}

		uint256 lpSupply = pool.amount;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(tokenId, pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(pool.allocPoint).div(totalAllocPoint[tokenId]);
            accPerShare = accPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accPerShare).div(1e12).sub(user.rewardDebt);
    }
	

	function massUpdatePools(uint tokenId) public {
        uint256 length = poolNum[tokenId];
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(tokenId, pid);
        }
    }


	function updatePool(uint tokenId, uint256 _pid) public {
		require(tokenId < tokenIndex);
        PoolInfo storage pool = poolInfo[tokenId][_pid];
		TokenParam storage pram = tokenInfo[tokenId];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
		if(startBlock[tokenId] == 0){
			return;
		}

		uint256 lpSupply = pool.amount;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(tokenId, pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(pool.allocPoint).div(totalAllocPoint[tokenId]);
        MyToken(pram.myTokenAddr).mint(pram.devAddr, tokenReward.mul(pram.feeRate).div(100));
        MyToken(pram.myTokenAddr).mint(address(this), tokenReward);
        pool.accPerShare = pool.accPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }



	function deposit(uint tokenId, uint256 _pid, uint256 _amount) public {
		if(tokenId != 0){
			require(startBlock[tokenId] != 0);
			require(tokenInfo[tokenId].blkNumPriMine + startBlock[tokenId] <= block.number, "priority period");
		}
        PoolInfo storage pool = poolInfo[tokenId][_pid];
        UserInfo storage user = userInfo[tokenId][_pid][msg.sender];
        updatePool(tokenId, _pid);
		
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPerShare).div(1e12).sub(user.rewardDebt);
            safeTokenTransfer(tokenId, msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
		pool.amount = pool.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e12);
        emit Deposit(msg.sender,tokenId, _pid, _amount);
    }
	

	function delegateDeposit(address _user, uint tokenId, uint256 _pid, uint256 _amount, uint256 _lock_expire)  public onlyDelegate{
		PoolInfo storage pool = poolInfo[tokenId][_pid];
		UserInfo storage user = userInfo[tokenId][_pid][_user];
		updatePool(tokenId, _pid);
		if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPerShare).div(1e12).sub(user.rewardDebt);
            safeTokenTransfer(tokenId, _user, pending);
        }
		pool.lpToken.safeTransferFrom(delegateContract, address(this), _amount);
        user.amount = user.amount.add(_amount);
		user.lock_amount = user.lock_amount.add(_amount);
		user.lock_expire = _lock_expire;
		pool.amount = pool.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e12);
        emit Deposit(_user,tokenId, _pid, _amount);
	}
	

    function withdraw(uint tokenId, uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[tokenId][_pid];
        UserInfo storage user = userInfo[tokenId][_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
		if(user.lock_expire != 0){
			if(user.lock_expire > now){ 
				require(user.amount.sub(user.lock_amount) >= _amount,"lock amount");
			}
			else{ 
				user.lock_expire = 0;
				user.lock_amount = 0;
			}
		}
        updatePool(tokenId, _pid);
        uint256 pending = user.amount.mul(pool.accPerShare).div(1e12).sub(user.rewardDebt);
        safeTokenTransfer(tokenId, msg.sender, pending);
        user.amount = user.amount.sub(_amount);
		pool.amount = pool.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender,tokenId, _pid, _amount);
    }

	function safeTokenTransfer(uint tokenId, address _to, uint256 _amount) internal {
		TokenParam storage pram = tokenInfo[tokenId];
		uint256 Bal = ERC20(pram.myTokenAddr).balanceOf(address(this));
        if (_amount > Bal) {
            ERC20(pram.myTokenAddr).transfer(_to, Bal);
        } else {
            ERC20(pram.myTokenAddr).transfer(_to, _amount);
        }
    }

	function getMultiplier(uint tokenId, uint256 _from, uint256 _to) public view returns (uint256) {
		TokenParam storage pram = tokenInfo[tokenId];
		uint start = startBlock[tokenId];
		uint bonusEndBlock = start.add(pram.blkNum1st);
		
		if(_to <= bonusEndBlock.add(pram.blkNum2nd)){
			if(_to <= bonusEndBlock){
				if(pram.blkNum1st == 0){
					return 0;
				}
				else{
					return _to.sub(_from).mul(pram.amount1st).div(pram.blkNum1st).mul(100).div(pram.feeRate.add(100));
				}
			}
			else if(_from >= bonusEndBlock){
				if(pram.blkNum2nd == 0){
					return 0;
				}
				else{
					return _to.sub(_from).mul(pram.amount2nd).div(pram.blkNum2nd).mul(100).div(pram.feeRate.add(100));
				}
			}
			else{
				uint first;
				uint sec;
				if(pram.blkNum1st == 0){
					first = 0;
				}
				else{
					first =  bonusEndBlock.sub(_from).mul(pram.amount1st).div(pram.blkNum1st);
				}
				if(pram.blkNum2nd == 0){
					sec = 0;
				}
				else{
					sec = _to.sub(bonusEndBlock).mul(pram.amount2nd).div(pram.blkNum2nd);
				}
			    return first.add(sec).mul(100).div(pram.feeRate.add(100));
			}
		}
		else{
			if(pram.blkNum3rd == 0){
				return 0;
			}
			uint blockHalfstart = bonusEndBlock.add(pram.blkNum2nd);
			uint num = _to.sub(blockHalfstart).div(pram.blkNum3rd).add(1);
			uint perBlock = pram.amount3rd.div(2 ** num).div(pram.blkNum3rd);
			return _to.sub(_from).mul(perBlock).mul(100).div(pram.feeRate.add(100));
		}
    }

	function dev(uint tokenId, address _devAddr) public {
        require(msg.sender == tokenInfo[tokenId].devAddr, "dev: wut?");
        tokenInfo[tokenId].devAddr = _devAddr;
    }
	

	function viewPoolInfo(uint tokenId) public view returns (PoolInfo[] memory){
		uint256 length = poolNum[tokenId];
		PoolInfo[] memory ret = new PoolInfo[](length);
		for (uint256 pid = 0; pid < length; ++pid) {
            ret[pid] = poolInfo[tokenId][pid];
        }
		return ret;
	}
	

	function viewTokenInfo() public view returns (TokenParam[] memory){
		TokenParam [] memory ret = new TokenParam[](tokenIndex);
		for(uint256 index = 0; index < tokenIndex; ++index){
			ret[index]=tokenInfo[index];
		}
		return ret;
	}
}