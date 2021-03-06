--[[
 - Author: yoosan, SYSUDNLP Group
 - Date: 6/21/16, 2016.
 - Licence MIT
--]]

require 'init.lua'

local cmd = torch.CmdLine()
cmd:option('-task', 'SICK', 'training dataset for modeling sentence pair')
cmd:option('-structure', 'lstm', 'model structure')
cmd:option('-mem_dim', 150, 'dimension of memory')
cmd:option('-n_epoches', 10, 'number of epoches for training')
cmd:option('-lr', 0.05, 'learning rate')
cmd:option('-batch_size', 25, 'batch size')
cmd:option('-feats_dim', 50, 'features dimensions')
local config = cmd:parse(arg or {})

header(config.task .. ' dataset for modeling sentence pair')

-- load word embedding and dataset
local data_dir = 'data/' .. config.task:lower()
local vocab = utils.Vocab(data_dir .. '/vocab-cased.txt')
local emb_vecs = utils.load_embedding('data', vocab)
config.emb_vecs = emb_vecs

local dset_train = utils.read_dataset(data_dir .. '/train/', vocab)
local dset_test = utils.read_dataset(data_dir .. '/test/', vocab)
local dset_train, dset_dev = utils.split_data(dset_train, 0.1)
--local dset_dev = utils.read_dataset(data_dir .. '/dev/', vocab)

printf('size of vocab = %d\n', vocab.size)
printf('number of train = %d\n', dset_train.size)
printf('number of dev   = %d\n', dset_dev.size)
printf('number of test  = %d\n', dset_test.size)

-- train and evaluate
local trainer = Trainer(config)
trainer:print_config()

function run(tr, n_epoches, dset_train, dset_dev, dset_test)
    header('Training model ... ')
    local train_start = sys.clock()
    local best_score = -1.0
    local best_params
    local best_trainer = tr
    for i = 1, n_epoches do
        local start = sys.clock()
        printf('-- epoch %d \n', i)
        tr:train(dset_train)
        printf('-- finished epoch in %.2fs\n', sys.clock() - start)
        local predictions = tr:eval(dset_dev)
        local dev_score
        if tr.task == 'SICK' then
            local pearson_score = stats.pearson(predictions, dset_dev.labels)
            local spearman_score = stats.spearmanr(predictions, dset_dev.labels)
            local mse_score = stats.mse(predictions, dset_dev.labels)
            printf('-- Dev pearson = %.4f, spearmanr = %.4f, mse = %.4f \n',
                pearson_score, spearman_score, mse_score)
            dev_score = pearson_score
        elseif tr.task == 'MSRP' then
            local accuracy = stats.accuracy(predictions, dset_dev.labels)
            local f1 = stats.f1(predictions, dset_dev.labels)
            printf('-- Dev accuracy = %.4f, f1 score = %.4f \n', accuracy, f1)
            dev_score = accuracy
        elseif tr.task == 'WQA' then
            local qids = dset_dev.qids
            local qa_dict = {}
            for i = 1, dset_dev.size do
                qa_dict[qids[i]] = {}
            end
            for i = 1, dset_dev.size do
                table.insert(qa_dict[qids[i]], {dset_dev.labels[i], predictions[i]})
            end
            local map_score = stats.MAP(qa_dict)
            local mrr_score = stats.MRR(qa_dict)
            printf('-- Dev MAP = %.4f, MRR score = %.4f \n', map_score, mrr_score)
            dev_score = map_score
        else
            local accuracy = stats.accuracy(predictions, dset_dev.labels)
            printf('-- Dev accuracy = %.4f \n', accuracy)
            dev_score = accuracy
        end
        if dev_score > best_score then
            best_score = dev_score
            best_trainer.params:copy(tr.params)
        end
    end
    printf('finished training in %.2fs\n', sys.clock() - train_start)
    header('Evaluating on test set')
    printf('-- using model with dev score = %.4f\n', best_score)
    local test_preds = best_trainer:eval(dset_test)
    local flag = false
    if tr.task == 'SICK' then
        local pearson_score = stats.pearson(test_preds, dset_test.labels)
        local spearman_score = stats.spearmanr(test_preds, dset_test.labels)
        local mse_score = stats.mse(test_preds, dset_test.labels)
        printf('-- Test pearson = %.4f, spearmanr = %.4f, mse = %.4f \n',
            pearson_score, spearman_score, mse_score)
        if pearson_score > 0.87 then flag = true end
    elseif tr.task == 'MSRP' then
        local accuracy = stats.accuracy(test_preds, dset_test.labels)
        local f1 = stats.f1(test_preds, dset_test.labels)
        printf('-- Test accuracy = %.4f, f1 score = %.4f \n', accuracy, f1)
    elseif tr.task == 'WQA' then
        local qids = dset_test.qids
        local qa_dict = {}
        for i = 1, dset_test.size do
            qa_dict[qids[i]] = {}
        end
        for i = 1, dset_test.size do
            table.insert(qa_dict[qids[i]], {dset_test.labels[i], test_preds[i]})
        end
        local map_score = stats.MAP(qa_dict)
        local mrr_score = stats.MRR(qa_dict)
        printf('-- Test MAP = %.4f, MRR score = %.4f \n', map_score, mrr_score)
    else
        local accuracy = stats.accuracy(test_preds, dset_test.labels)
        printf('-- Test accuracy = %.4f \n', accuracy)
    end
    if flag then
    print('save parameters')
    local path = 'data/params/params-' .. tr.task .. '-' .. tr.structure .. '.t7'
    best_trainer:save(path)
    end
end

function test(ts, dset_test)
    local models_dict = {
        lstm = 'Sequential LSTMs',
        gru = 'Sequential GRUs',
        treelstm = 'Dependency Tree-LSTMs',
        treegru = 'Dependency Tree-GRUs',
        atreelstm = 'Attentive Tree-LSTMs',
        atreegru = 'Attentive Tree-GRUs',
    }
    header('Evaluating on ' .. config.task ..
            ', model is ' .. models_dict[config.structure])
    local test_preds = ts:eval(dset_test)
    if ts.task == 'SICK' then
        local pearson_score = stats.pearson(test_preds, dset_test.labels)
        local spearman_score = stats.spearmanr(test_preds, dset_test.labels)
        local mse_score = stats.mse(test_preds, dset_test.labels)
        printf('-- Test pearson = %.4f, spearmanr = %.4f, mse = %.4f \n',
            pearson_score, spearman_score, mse_score)
    elseif ts.task == 'MSRP' then
        local accuracy = stats.accuracy(test_preds, dset_test.labels)
        local f1 = stats.f1(test_preds, dset_test.labels)
        printf('-- Test accuracy = %.4f, f1 score = %.4f \n', accuracy, f1)
    elseif tr.task == 'WQA' then
        local qids = dset_test.qids
        local qa_dict = {}
        for i = 1, dset_test.size do
            qa_dict[qids[i]] = {}
        end
        for i = 1, dset_test.size do
            table.insert(qa_dict[qids[i]], {dset_test.labels[i], test_preds[i]})
        end
        local map_score = stats.MAP(qa_dict)
        local mrr_score = stats.MRR(qa_dict)
        printf('-- Test MAP = %.4f, MRR score = %.4f \n', map_score, mrr_score)
    else
        local accuracy = stats.accuracy(test_preds, dset_test.labels)
        printf('-- Test accuracy = %.4f \n', accuracy)
    end
end

run(trainer, config.n_epoches, dset_train, dset_dev, dset_test)

--local path = 'data/params/params-' .. config.task .. '-' .. config.structure .. '.t7'
--local model = torch.load(path)
--model.config.emb_vecs = emb_vecs
--local tester = Tester(model.config)
--tester.params:copy(model.params)
--test(tester, dset_test)