//
//  VANTIQUIViewController.m
//  vantiq-ui-ios
//
//  Created by Michael Swan on 09/13/2024.
//  Copyright (c) 2024 Michael Swan. All rights reserved.
//

#import "VANTIQUIViewController.h"
#import "VantiqUI.h"

#define VANTIQ_SERVER   @"https://cbfc965a30d7.ngrok.app"

@interface VANTIQUIViewController () {
    VantiqUI *vui;
    NSMutableString *results;
    NSString *lastVantiqID;
}
@property (weak, nonatomic) IBOutlet UITextView *textResults;
@property (strong, atomic) NSNumber *queueCount;
@end

// macro to add text to our UITextView field, scroll to the last entry and,
// as a side effect, decrement our outstanding operations count
#define AddToResults(resultStr) dispatch_async(dispatch_get_main_queue(), ^ {\
    [self appendAndScroll:[NSString stringWithFormat:@"%@", resultStr] updateCount:true];\
});
#define AddToText(resultStr) dispatch_async(dispatch_get_main_queue(), ^ {\
    [self appendAndScroll:[NSString stringWithFormat:@"%@", resultStr] updateCount:false];\
});

@implementation VANTIQUIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    results = [NSMutableString new];
    _queueCount = [NSNumber numberWithInt:20];
    AddToText(@"Authenticating...");
    
    vui = [[VantiqUI alloc] init:VANTIQ_SERVER namespace:@"" completionHandler:^(NSDictionary *response) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            NSString *authValid = [response objectForKey:@"authValid"];
            NSString *preferredUsername = [response objectForKey:@"preferredUsername"];
            NSString *stateStr;
            if (authValid && [authValid isEqualToString:@"true"]) {
                stateStr = [NSString stringWithFormat:@"Auth token verified for user %@", preferredUsername];
                AddToText(stateStr);
                [self runSomeTests];
            } else {
                NSString *serverType = [response objectForKey:@"serverType"];
                if (serverType) {
                    [self initiateAuth:serverType];
                } else {
                    stateStr = [NSString stringWithFormat:@"No server type found for %@ (%@)", VANTIQ_SERVER,
                        [response objectForKey:@"errorStr"]];
                    AddToText(stateStr);
                }
            }
        });
    }];
}

/*
 *  appendAndScroll
 *      - given some text, add that text to our mutable results string, then
 *          update the UITextView and scroll to the latest entry
 */
- (void)appendAndScroll:(NSString *)text updateCount:(BOOL)updateCount {
    [results appendString:[NSString stringWithFormat:@"%@\n", text]];
    _textResults.text = results;

    // scroll to the bottom of the results
    NSRange range = NSMakeRange(_textResults.text.length - 1, 1);
    [_textResults scrollRangeToVisible:range];
    
    if (updateCount) {
        _queueCount = [NSNumber numberWithInt:[_queueCount intValue] - 1];
        if ([_queueCount intValue] == 0) {
            AddToText(@"Finished tests.");
        }
    }
}

- (void)initiateAuth:(NSString *)serverType {
    if ([serverType isEqualToString:@"Internal"]) {
        [self->vui authWithInternal:@"swan" password:@"3367whit" completionHandler:^(NSDictionary *response) {
            [self finishAuth:response];
        }];
    } else {
        [self->vui authWithOAuth:@"vantiqreact" clientId:@"vantiqReact" completionHandler:^(NSDictionary *response) {
            [self finishAuth:response];
        }];
    }
}

- (void)finishAuth:(NSDictionary *)authResponse {
    dispatch_async(dispatch_get_main_queue(), ^ {
        NSString *errorStr = [authResponse objectForKey:@"errorStr"];
        if (!errorStr.length) {
            // remember the username
            AddToText(@"Authentication complete.");
            [self runSomeTests];
        } else {
            NSString *errStr = [NSString stringWithFormat:@"viewDidLoad error: %@", errorStr];
            AddToText(errStr);
        }
    });
}

- (void)runSomeTests {
    int i;
    for (i = 0; i < 2; i++) {
        if (i == 0) {
            AddToText(@"Starting tests...");
        } else {
            AddToText(@"Sleeping...");
            [NSThread sleepForTimeInterval:120];
            AddToText(@"Restarting tests...");
        }
        [self runSelectTest:@"system.types" props:@[] where:NULL sort:NULL limit:-1];
        [NSThread sleepForTimeInterval:.3];
        [self runSelectTest:@"system.types" props:@[@"name", @"naturalKey"] where:NULL sort:NULL limit:-1];
        [NSThread sleepForTimeInterval:.3];
        [self runSelectTest:@"system.types" props:@[@"name", @"naturalKey"] where:@"{\"name\":\"ArsRuleSnapshot\"}" sort:NULL limit:-1];
        [NSThread sleepForTimeInterval:.3];
        [self runSelectTest:@"system.types" props:@[@"name", @"_id"] where:NULL sort:@"{\"name\":-1}" limit:-1];
        [NSThread sleepForTimeInterval:.3];
        [self runSelectTest:@"system.types" props:@[] where:NULL sort:NULL limit:2];
        
        [NSThread sleepForTimeInterval:.3];
        [self runCountTest:@"system.types" where:NULL];
        [NSThread sleepForTimeInterval:.3];
        [self runCountTest:@"system.types" where:@"{\"name\":\"ArsRuleSnapshot\"}"];
        [NSThread sleepForTimeInterval:.3];
        [self runCountTest:@"system.types" where:@"{\"ars_version\":{\"$gt\":5}}"];
        
        [NSThread sleepForTimeInterval:.3];
        [self runInsertTest:@"TestType" object:@"{\"intValue\":42,\"uniqueString\":\"42\"}"];
        [NSThread sleepForTimeInterval:.3];
        [self runInsertTest:@"TestType" object:@"{\"intValue\":43,\"uniqueString\":\"43\",\"stringValue\":\"A String.\"}"];
        
        [NSThread sleepForTimeInterval:.3];
        [self runUpsertTest:@"TestType" object:@"{\"intValue\":44,\"uniqueString\":\"A Unique String.\"}"];
        [NSThread sleepForTimeInterval:.3];
        [self runUpsertTest:@"TestType" object:@"{\"intValue\":45,\"uniqueString\":\"A Unique String.\"}"];
        
        [NSThread sleepForTimeInterval:.3];
        [self runUpdateTest:@"TestType" id:lastVantiqID object:@"{\"stringValue\":\"Updated String.\"}"];
        
        [NSThread sleepForTimeInterval:.3];
        [self runSelectOneTest:@"TestType" id:lastVantiqID];
        
        [NSThread sleepForTimeInterval:.3];
        [self runPublishTest:@"/vantiq" message:@"{\"intValue\":42}"];
        
        [NSThread sleepForTimeInterval:.3];
        [self runExecuteTest:@"sumTwo" params:@"[35, 21]"];
        [NSThread sleepForTimeInterval:.3];
        [self runExecuteTest:@"sumTwo" params:@"{\"val2\":35, \"val1\":21}"];
        
        [NSThread sleepForTimeInterval:.3];
        [self runDeleteOneTest:@"TestType" id:lastVantiqID];
        
        [NSThread sleepForTimeInterval:.3];
        [self runDeleteTest:@"TestType" where:@"{\"intValue\":42}"];
        [NSThread sleepForTimeInterval:.3];
        [self runDeleteTest:@"TestType" where:@"{\"intValue\":43}"];
    }
}

- (void)runSelectTest:(NSString *)type props:(NSArray *)props where:(NSString *)where sort:(NSString *)sort limit:(int)limit {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v select:type props:props where:where sort:sort limit:limit completionHandler:^(NSArray *data, NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr = @"";
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"select(%@) returns %lu records.", type, (unsigned long)[data count]];
                        } else {
                            [self->vui formError:response error:error resultStr:&resultStr];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"select(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"select(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
}

- (void)runCountTest:(NSString *)type where:(NSString *)where {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v count:type where:where completionHandler:^(int count, NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"count(%@) returns count %d.", type, count];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"count(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"count(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
}

- (void)runInsertTest:(NSString *)type object:(NSString *)object {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v insert:type object:object completionHandler:^(NSDictionary *data, NSHTTPURLResponse *response, NSError *error) {
                    if (data) {
                        // remember the record ID of this insert
                        self->lastVantiqID = [data objectForKey:@"_id"];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"insert(%@) successful.", type];
                        } else {
                            resultStr = @"Please make sure the type 'TestType' is defined. See the documentation.";
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"insert(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"insert(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
};

- (void)runUpsertTest:(NSString *)type object:(NSString *)object {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v upsert:type object:object completionHandler:^(NSDictionary *data, NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"upsert(%@) successful.", type];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"upsert(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"upsert(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
};

- (void)runDeleteTest:(NSString *)type where:(NSString *)where {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v delete:type where:where completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"delete(%@) successful.", type];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"delete(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"delete(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
}

- (void)runDeleteOneTest:(NSString *)type id:(NSString *)ID {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v deleteOne:type id:ID completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"deleteOne(%@) successful.", type];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"deleteOne(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"deleteOne(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
}

- (void)runPublishTest:(NSString *)topic message:(NSString *)message {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v publish:topic message:message completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"publish(%@) successful.", topic];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"publish(%@) auth fails", topic];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"publish(%@) auth unknown", topic];
            AddToResults(resultStr);
        }
    }];
}

- (void)runExecuteTest:(NSString *)procedure params:(NSString *)params {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v execute:procedure params:params completionHandler:^(NSDictionary *data, NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"procedure(%@) successful.", procedure];
                        } else {
                            resultStr = @"Please make sure the procedure 'AddTwo' is defined. See the documentation.";
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"procedure(%@) auth fails", procedure];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"procedure(%@) auth unknown", procedure];
            AddToResults(resultStr);
        }
    }];
}

- (void)runUpdateTest:(NSString *)type id:(NSString *)ID object:(NSString *)object {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v update:type id:ID object:object completionHandler:^(NSDictionary *data, NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"update(%@) successful.", type];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"update(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"update(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
};

- (void)runSelectOneTest:(NSString *)type id:(NSString *)ID {
    [vui ensureValidToken:^(NSDictionary *response) {
        NSString *resultStr;
        NSString *authValid = [response objectForKey:@"authValid"];
        if (authValid) {
            if ([authValid isEqualToString:@"true"]) {
                [self->vui.v selectOne:type id:ID completionHandler:^(NSArray *data, NSHTTPURLResponse *response, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        NSString *resultStr;
                        if (!error) {
                            resultStr = [NSString stringWithFormat:@"selectOne(%@) successful.", type];
                        }
                        AddToResults(resultStr);
                    });
                }];
            } else {
                resultStr = [NSString stringWithFormat:@"selectOne(%@) auth fails", type];
                AddToResults(resultStr);
            }
        } else {
            resultStr = [NSString stringWithFormat:@"selectOne(%@) auth unknown", type];
            AddToResults(resultStr);
        }
    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
