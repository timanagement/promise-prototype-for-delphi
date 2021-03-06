unit Promise.Proto;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.SyncObjs
;


{$REGION 'Interfaces'}
type
  TState = (Pending, Resolved, Rejected, Finished);

  EPromiseException = class(Exception);
  EInvalidPromiseStateException = class(EPromiseException);

  IFailureReason<TFailure:Exception> = interface
    ['{A7C29DBC-D00B-4B5D-ABD6-3280F9F49971}']
    function GetReason: TFailure;
    property Reason: TFailure read GetReason;
  end;

  IPromise<TSuccess; TFailure:Exception> = interface;
  IPromiseAccess<TSuccess; TFailure:Exception> = interface;

  TFailureProc<TFailure:Exception> = reference to procedure (failure: IFailureReason<TFailure>);
  TPromiseInitProc<TResult; TFailure:Exception> = reference to procedure (const resolver: TProc<TResult>; const rejector: TFailureProc<TFailure>);
  TPipelineFunc<TSource, TSuccess; TFailure:Exception> = reference to function (value: TSource): IPromise<TSuccess, TFailure>;
  IFuture<TResult> = interface;

  TPromiseOp<TSuccess; TFailure:Exception> = record
  private
    FPromise: IpromiseAccess<TSuccess, TFailure>;
  private
    class function Create(const promise: IpromiseAccess<TSuccess, TFailure>): TPromiseOp<TSuccess, TFailure>; static;
    function ThenByInternal<TNextSuccess; TNextFailure:Exception>(
      const whenSuccess: TPipelineFunc<TSuccess, TNextSuccess, TNextFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TNextSuccess, TNextFailure>): IPromise<TNextSuccess, TNextFailure>;
  public
    function ThenBy<TNextSuccess>(const whenSuccess: TPipelineFunc<TSuccess, TNextSuccess, TFailure>): IPromise<TNextSuccess, TFailure>; overload;
    function ThenBy<TNextSuccess; TNextFailure:Exception>(
      const whenSuccess: TPipelineFunc<TSuccess, TNextSuccess, TNextFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TNextSuccess, TNextFailure>): IPromise<TNextSuccess, TNextFailure>; overload;
    function Catch<TNextFailure:Exception>(const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TNextFailure>): IPromise<TSuccess, TNextFailure>;
  end;

  IPromise<TSuccess; TFailure:Exception> = interface
    ['{19311A2D-7DDD-41CA-AD42-29FCC27179C5}']
    function GetFuture: IFuture<TSuccess>;
    function Done(const proc: TProc<TSuccess>): IPromise<TSuccess, TFailure>;
    function Fail(const proc: TFailureProc<TFailure>): IPromise<TSuccess, TFailure>;
    function ThenBy(const fn: TPipelineFunc<TSuccess, TSuccess, TFailure>): IPromise<TSuccess, TFailure>; overload;
    function ThenBy(
      const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>; overload;
    function Catch(const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
    function Op: TPromiseOp<TSuccess, TFailure>;

    property Future: IFuture<TSuccess> read GetFuture;
  end;

  IPromiseAccess<TSuccess; TFailure:Exception> = interface
    ['{D6A8317E-CF96-41A5-80EE-5FFB2D1D7676}']
    function GetValue: TSuccess;
    function GetFailure: IFailureReason<TFailure>;
    function GetState: TState;
    function GetSelf: IPromise<TSuccess, TFailure>;

    property State: TState read GetState;
    property Self: IPromise<TSuccess, TFailure> read GetSelf;
  end;

  IPromiseResolvable<TSuccess; TFailure:Exception> = interface
    function Resolve(value: TSuccess): IPromise<TSuccess, TFailure>;
    function Reject(value: IFailureReason<TFailure>): IPromise<TSuccess, TFailure>;
  end;

  IFuture<TResult> = interface
    ['{844488AD-0136-41F8-94B1-B7BA2EB0C019}']
    function GetValue: TResult;
    procedure Cancell;
    function WaitFor: boolean;

    property Value: TResult read GetValue;
  end;
{$ENDREGION}

{$REGION 'Entry Point'}

  TPromise = record
  public
    class function When<TSuccess>(const fn: TFunc<TSuccess>): IPromise<TSuccess, Exception>; overload; static;
    class function When<TSuccess>(const initializer: TPromiseInitProc<TSuccess, Exception>): IPromise<TSuccess, Exception>; overload; static;
    class function When<TSuccess; TFailure:Exception>(const initializer: TPromiseInitProc<TSuccess, TFailure>): IPromise<TSuccess, TFailure>; overload; static;
    class function Resolve<TSuccess>(value: TSuccess): IPromise<TSuccess, Exception>; static;
    class function Reject<TSuccess; TFailure:Exception>(value: TFailure): IPromise<TSuccess, TFailure>; overload; static;
    class function Reject<TFailure:Exception>(value: TFailure): IPromise<TObject, TFailure>; overload; static;
  end;
{$ENDREGION}

{$REGION 'Implementaion types'}
  TDeferredTask<TResult; TFailure:Exception> = class (TInterfacedObject, IFuture<TResult>)
  strict private var
    FThread: TThread;
    FSignal: TEvent;
    FResult: TResult;
  private var
    FPromise: IPromiseResolvable<TResult,TFailure>;
  private
    function GetValue: TResult;
    procedure NotifyThreadTerminated(Sender: TObject);
  protected
    { IDeferredTask<TResult> }
    procedure Cancell;
    function WaitFor: boolean;
  protected
    procedure DoExecute(const initializer: TPromiseInitProc<TResult, TFailure>);
  public
    constructor Create(const promise: IPromiseResolvable<TResult,TFailure>; const initializer: TPromiseInitProc<TResult,TFailure>); overload;
    destructor Destroy; override;
  end;

  TFailureReason<TFailure:Exception>  = class(TInterfacedObject, IFailureReason<TFailure>)
  private
    FReason: TFailure;
  protected
    function GetReason: TFailure;
  public
    constructor Create(const reason: TFailure);
    destructor Destroy; override;
  end;

  TAbstractPromise<TSuccess; TFailure:Exception> = class abstract (TInterfacedObject, IPromiseAccess<TSuccess, TFailure>)
  private
    function GetState: TState;
    function GetSelf: IPromise<TSuccess, TFailure>;
    function GetValue: TSuccess;
    function GetFailure: IFailureReason<TFailure>;
  protected
    function GetSelfInternal: IPromise<TSuccess, TFailure>; virtual; abstract;
    function GetStateInternal: TState; virtual; abstract;
    function GetValueInternal: TSuccess; virtual; abstract;
    function GetFailureInternal: IFailureReason<TFailure>; virtual; abstract;
  protected
    function ThenByInternal(
      const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
  end;

  TDeferredObject<TSuccess; TFailure:Exception> = class (TAbstractPromise<TSuccess, TFailure>, IPromise<TSuccess, TFailure>, IPromiseResolvable<TSuccess,TFailure>)
  private
    FState: TState;
    FSuccess: TSuccess;
    FFailure: IFailureReason<TFailure>;
    FFuture: IFuture<TSuccess>;
  private
    function GetFuture: IFuture<TSuccess>;
    procedure AssertState(const acceptable: boolean; const msg: string);
  protected
    function GetSelfInternal: IPromise<TSuccess, TFailure>; override;
    function GetStateInternal: TState; override;
    function GetValueInternal: TSuccess; override;
    function GetFailureInternal: IFailureReason<TFailure>; override;
  protected
    { IPromise<TSuccess, TFailure> }
    function Done(const proc: TProc<TSuccess>): IPromise<TSuccess, TFailure>;
    function Fail(const proc: TFailureProc<TFailure>): IPromise<TSuccess, TFailure>;
    function ThenBy(const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>): IPromise<TSuccess, TFailure>; overload;
    function ThenBy(
      const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>; overload;
    function Catch(const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
    function Op: TPromiseOp<TSuccess, TFailure>;
  protected
    { IPromiseResolvable<TSuccess,TFailure> }
    function Resolve(value: TSuccess): IPromise<TSuccess, TFailure>;
    function Reject(value: IFailureReason<TFailure>): IPromise<TSuccess, TFailure>;
  public
    constructor Create(const initializer: TPromiseInitProc<TSuccess,TFailure>);
    destructor Destroy; override;
  end;

  TPipedPromise<TSuccessSource, TSuccess; TFailureSource, TFailure:Exception> =
    class (TAbstractPromise<TSuccess, TFailure>, IPromise<TSuccess, TFailure>, IPromiseResolvable<TSuccess, TFailure>)
  private
    FFuture: IFuture<TSuccess>;
    FPrevPromise: IPromiseAccess<TSuccessSource, TFailureSource>;
    FState: TState;
    FFailure: IFailureReason< TFailure>;
  private
    function GetFuture: IFuture<TSuccess>;
  protected
    function GetSelfInternal: IPromise<TSuccess, TFailure>; override;
    function GetStateInternal: TState; override;
    function GetValueInternal: TSuccess; override;
    function GetFailureInternal: IFailureReason<TFailure>; override;
  protected
    { IPromise<TSuccess, TFailure> }
    function Done(const proc: TProc<TSuccess>): IPromise<TSuccess, TFailure>;
    function Fail(const proc: TFailureProc<TFailure>): IPromise<TSuccess, TFailure>;
    function ThenBy(const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>): IPromise<TSuccess, TFailure>; overload;
    function ThenBy(
      const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>; overload;
    function Catch(const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
    function Op: TPromiseOp<TSuccess, TFailure>;
  protected
    { IPromiseResolvable<TSuccess, TFailure> }
    function Resolve(value: TSuccess): IPromise<TSuccess, TFailure>;
    function Reject(value: IFailureReason<TFailure>): IPromise<TSuccess, TFailure>;
  public
    constructor Create(
      const prev: IPromiseAccess<TSuccessSource, TFailureSource>;
      const whenSucces: TPipelineFunc<TSuccessSource,TSuccess,TFailure>;
      const whenFailure: TPipelineFunc<IFailureReason<TFailureSource>,TSuccess,TFailure>); overload;
    destructor Destroy; override;
  end;

  TTerminatedPromise<TResult; TFailure:Exception> = class(TInterfacedObject, IPromise<TResult, TFailure>, IPromiseResolvable<TResult,TFailure>)
  private
    FPrevPromise: IPromiseAccess<TResult, TFailure>;
    FState: TState;
    FFuture: IFuture<TResult>;
    FDoneActions: TList<TProc<TResult> >;
    FFailActions: TList<TFailureProc<TFailure>>;
  private
    function GetFuture: IFuture<TResult>;
    function GetState: TState;
  protected
    { IPromise<TSuccess, TFailure> }
    function Done(const proc: TProc<TResult>): IPromise<TResult, TFailure>;
    function Fail(const proc: TFailureProc<TFailure>): IPromise<TResult, TFailure>;
    function ThenBy(const fn: TPipelineFunc<TResult, TResult, TFailure>): IPromise<TResult, TFailure>; overload;
    function ThenBy(
      const whenSuccess: TPipelineFunc<TResult, TResult, TFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>; overload;
    function Catch(const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>;
    function Op: TPromiseOp<TResult, TFailure>;
  protected
    { IPromiseResolvable<TResult,TFailure> }
    function Resolve(value: TResult): IPromise<TResult, TFailure>;
    function Reject(value: IFailureReason<TFailure>): IPromise<TResult, TFailure>;
  public
    constructor Create(const prev: IPromiseAccess<TResult, TFailure>);
    destructor Destroy; override;
  end;

  TPromiseValue<TResult; TFailure:Exception> = class(TAbstractPromise<TResult, TFailure>, IPromise<TResult, TFailure>)
  private type
    TFuture = class(TInterfacedObject, IFuture<TResult>)
    private
      FValue: TResult;
    protected
      { IFuture<TResult> }
      function GetValue: TResult;
      procedure Cancell;
      function WaitFor: boolean;
    public
      constructor Create(value: TResult);
    end;
  private
    FSuccess: TResult;
    FFailure: IFailureReason< TFailure>;
    FState: TState;
  private
    function GetFuture: IFuture<TResult>;
  protected
    function GetSelfInternal: IPromise<TResult, TFailure>; override;
    function GetStateInternal: TState; override;
    function GetValueInternal: TResult; override;
    function GetFailureInternal: IFailureReason<TFailure>; override;
  protected
    { IPromise<TResult, TFailure> }
    function Done(const proc: TProc<TResult>): IPromise<TResult, TFailure>;
    function Fail(const proc: TFailureProc<TFailure>): IPromise<TResult, TFailure>;
    function ThenBy(const fn: TPipelineFunc<TResult, TResult, TFailure>): IPromise<TResult, TFailure>; overload;
    function ThenBy(
      const whenSuccess: TPipelineFunc<TResult, TResult, TFailure>;
      const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>; overload;
    function Catch(const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>;
    function Op: TPromiseOp<TResult, TFailure>;
  public
    class function Resolve(success: TResult): TPromiseValue<TResult,TFailure>; static;
    class function Reject(failure: IFailureReason<TFailure>): TPromiseValue<TResult,TFailure>; static;
  end;
{$ENDREGION}

implementation

{ TPromiseOp<TSuccess, TFailure> }

class function TPromiseOp<TSuccess, TFailure>.Create(
  const promise: IpromiseAccess<TSuccess, TFailure>): TPromiseOp<TSuccess, TFailure>;
begin
  Assert(Assigned(promise));

  Result.FPromise := promise;
end;

function TPromiseOp<TSuccess, TFailure>.ThenBy<TNextSuccess>(
  const whenSuccess: TPipelineFunc<TSuccess, TNextSuccess, TFailure>): IPromise<TNextSuccess, TFailure>;
var
  p: IPromiseAccess<TSuccess, TFailure>;
begin
  p := FPromise;

  Result := ThenByInternal<TNextSuccess, TFailure>(
    whenSuccess,

    function (value: IFailureReason<TFailure>): IPromise<TNextSuccess,TFailure>
    begin
      Result := TPromiseValue<TNextSuccess,TFailure>.Reject(p.GetFailure);
    end
  );
end;

function TPromiseOp<TSuccess, TFailure>.Catch<TNextFailure>(
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TNextFailure>): IPromise<TSuccess, TNextFailure>;
var
  p: IPromiseAccess<TSuccess, TFailure>;
begin
  p := FPromise;

  Result := ThenByInternal<TSuccess, TNextFailure>(
    function (value: TSuccess): IPromise<TSuccess,TNextFailure>
    begin
      Result := TPromiseValue<TSuccess, TNextFailure>.Resolve(p.GetValue);
    end,

    whenfailure
  );
end;

function TPromiseOp<TSuccess, TFailure>.ThenBy<TNextSuccess, TNextFailure>(
  const whenSuccess: TPipelineFunc<TSuccess, TNextSuccess, TNextFailure>;
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TNextSuccess, TNextFailure>): IPromise<TNextSuccess, TNextFailure>;
begin
  Result := ThenByInternal<TNextSuccess, TNextFailure>(whenSuccess, whenfailure);
end;

function TPromiseOp<TSuccess, TFailure>.ThenByInternal<TNextSuccess, TNextFailure>(
  const whenSuccess: TPipelineFunc<TSuccess, TNextSuccess, TNextFailure>;
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TNextSuccess, TNextFailure>): IPromise<TNextSuccess, TNextFailure>;
var
  locker: TObject;
begin
  locker := TObject(FPromise);
  TMonitor.Enter(locker);
  try
    Result := TPipedPromise<TSuccess,TNextSuccess,TFailure,TNextFailure>.Create(FPromise, whenSuccess, whenfailure);
  finally
    TMonitor.Exit(locker);
  end;
end;

{ TDefferredManager }

class function TPromise.When<TSuccess>(
  const fn: TFunc<TSuccess>): IPromise<TSuccess, Exception>;
begin
  Result :=
    TDeferredObject<TSuccess,Exception>
    .Create(
      procedure (const resolver: TProc<TSuccess>; const rejector: TFailureProc<Exception>)
      var
        r: TSuccess;
      begin
        if Assigned(fn) then begin
          r := fn;
        end
        else begin
          r := System.Default(TSuccess);
        end;
        resolver(r);
      end
    );
end;

class function TPromise.Reject<TFailure>(
  value: TFailure): IPromise<TObject, TFailure>;
begin
  Result := Reject<TObject,TFailure>(value);
end;

class function TPromise.Reject<TSuccess,TFailure>(
  value: TFailure): IPromise<TSuccess, TFailure>;
begin
  Result :=
    TDeferredObject<TSuccess,TFailure>
    .Create(
      procedure (const resolver: TProc<TSuccess>; const rejector: TFailureProc<TFailure>)
      begin
        rejector(TFailureReason<TFailure>.Create(value));
      end
    );
end;

class function TPromise.Resolve<TSuccess>(
  value: TSuccess): IPromise<TSuccess, Exception>;
begin
  Result :=
    TDeferredObject<TSuccess,Exception>
    .Create(
      procedure (const resolver: TProc<TSuccess>; const rejector: TFailureProc<Exception>)
      begin
        resolver(value);
      end
    );
end;

class function TPromise.When<TSuccess, TFailure>(
  const initializer: TPromiseInitProc<TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  Result :=
    TDeferredObject<TSuccess,TFailure>
    .Create(initializer)
end;

class function TPromise.When<TSuccess>(
  const initializer: TPromiseInitProc<TSuccess, Exception>): IPromise<TSuccess, Exception>;
begin
  Result := When<TSuccess,Exception>(initializer);
end;

{ TDefferredTask<TResult> }

procedure TDeferredTask<TResult,TFailure>.Cancell;
begin

end;

constructor TDeferredTask<TResult, TFailure>.Create(
  const promise: IPromiseResolvable<TResult,TFailure>;
  const initializer: TPromiseInitProc<TResult, TFailure>);
begin
  FPromise := promise;
  FSignal := TEvent.Create;

  FThread := TThread.CreateAnonymousThread(
    procedure
    begin
      Self.DoExecute(initializer);
    end
  );

  FThread.OnTerminate := Self.NotifyThreadTerminated;
  FThread.Start;
end;

destructor TDeferredTask<TResult,TFailure>.Destroy;
begin
  FreeAndNil(FSignal);
  inherited;
end;

procedure TDeferredTask<TResult,TFailure>.DoExecute(const initializer: TPromiseInitProc<TResult, TFailure>);
var
  obj: TObject;
begin
  try
    initializer(
      procedure (value: TResult)
      begin
        FResult := value;
        FPromise.Resolve(value);
      end,
      procedure (value: IFailureReason<TFailure>)
      begin
        FPromise.Reject(value);
      end
    );
  except
    obj := AcquireExceptionObject;
    FPromise.Reject(TFailureReason<TFailure>.Create(obj as TFailure));
  end;

  FSignal.SetEvent;
end;

function TDeferredTask<TResult,TFailure>.GetValue: TResult;
begin
  Self.WaitFor;

  Result := FResult;
end;

procedure TDeferredTask<TResult, TFailure>.NotifyThreadTerminated(
  Sender: TObject);
begin
  FPromise := nil;
end;

function TDeferredTask<TResult, TFailure>.WaitFor: boolean;
begin
  Result := false;
  if Assigned(FThread) then begin
    if not FThread.Finished then begin
      Result := FSignal.WaitFor = wrSignaled;
    end;
    FPromise := nil;
  end;

  if TThread.CurrentThread.ThreadID = MainThreadID then begin
    while not CheckSynchronize do TThread.Sleep(100);
  end;
end;

{ TFailureReason<TFailure> }

constructor TFailureReason<TFailure>.Create(const reason: TFailure);
begin
  FReason := reason;
end;

destructor TFailureReason<TFailure>.Destroy;
begin
  FReason.Free;
  inherited;
end;

function TFailureReason<TFailure>.GetReason: TFailure;
begin
  Result := FReason;
end;

{ TAbstractPromise<TSuccess, TFailure> }

function TAbstractPromise<TSuccess, TFailure>.GetFailure: IFailureReason<TFailure>;
begin
  Result := Self.GetFailureInternal;
end;

function TAbstractPromise<TSuccess, TFailure>.GetState: TState;
begin
  Result := Self.GetStateInternal;
end;

function TAbstractPromise<TSuccess, TFailure>.GetValue: TSuccess;
begin
  Result := Self.GetValueInternal;
end;

function TAbstractPromise<TSuccess, TFailure>.GetSelf: IPromise<TSuccess, TFailure>;
begin
  Result := Self.GetSelfInternal;
end;

function TAbstractPromise<TSuccess, TFailure>.ThenByInternal(
  const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>;
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    Result := TPipedPromise<TSuccess, TSuccess, TFailure, TFailure>.Create(
      Self,
      function (value: TSuccess): IPromise<TSuccess, TFailure>
      begin
        if Assigned(whenSuccess) then begin
          Result := whenSuccess(value);
        end
        else begin
          Result := TPromiseValue<TSuccess, TFailure>.Resolve(value);
        end;
      end,

      function (value: IFailureReason<TFailure>): IPromise<TSuccess, TFailure>
      begin
        if Assigned(whenfailure) then begin
          Result := whenfailure(value);
        end
        else begin
          Result := TPromiseValue<TSuccess, TFailure>.Reject(value);
        end;
      end
    );
  finally
    TMonitor.Exit(Self);
  end;
end;

{ TDeferredObject<TSuccess, TFailure> }

destructor TDeferredObject<TSuccess, TFailure>.Destroy;
begin
  inherited;
end;

procedure TDeferredObject<TSuccess, TFailure>.AssertState(
  const acceptable: boolean; const msg: string);
begin
  if not acceptable then begin
    FState := TState.Pending;

    raise EInvalidPromiseStateException.Create(msg);
  end;
end;

function TDeferredObject<TSuccess, TFailure>.Catch(
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  Result := Self.ThenByInternal(nil, whenfailure);
end;

constructor TDeferredObject<TSuccess, TFailure>.Create(const initializer: TPromiseInitProc<TSuccess,TFailure>);
begin
  FFuture := TDeferredTask<TSuccess,TFailure>.Create(Self, initializer);
end;

function TDeferredObject<TSuccess, TFailure>.Done(
  const proc: TProc<TSuccess>): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    Result := TTerminatedPromise<TSuccess, TFailure>.Create(Self).Done(proc);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TDeferredObject<TSuccess, TFailure>.Fail(
  const proc: TFailureProc<TFailure>): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    Result := TTerminatedPromise<TSuccess, TFailure>.Create(Self).Fail(proc);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TDeferredObject<TSuccess, TFailure>.ThenBy(
  const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>;
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  Assert(Assigned(whenSuccess));
  Assert(Assigned(whenfailure));

  Result := Self.ThenByInternal(whenSuccess, whenfailure);
end;

function TDeferredObject<TSuccess, TFailure>.ThenBy(
  const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  Assert(Assigned(whenSuccess));

  Result := Self.ThenByInternal(whenSuccess, nil);
end;

function TDeferredObject<TSuccess, TFailure>.GetFailureInternal: IFailureReason<TFailure>;
begin
  Result := FFailure;
end;

function TDeferredObject<TSuccess, TFailure>.GetSelfInternal: IPromise<TSuccess, TFailure>;
begin
  Result := Self;
end;

function TDeferredObject<TSuccess, TFailure>.GetStateInternal: TState;
begin
  Result := FState;
end;

function TDeferredObject<TSuccess, TFailure>.GetFuture: IFuture<TSuccess>;
begin
  Result := FFuture;
end;

function TDeferredObject<TSuccess, TFailure>.GetValueInternal: TSuccess;
begin
  Result := FFuture.Value;
end;

function TDeferredObject<TSuccess, TFailure>.Op: TPromiseOp<TSuccess, TFailure>;
begin
  Result := TPromiseOp<TSuccess, TFailure>.Create(Self);
end;

function TDeferredObject<TSuccess, TFailure>.Resolve(
  value: TSuccess): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    AssertState(Self.GetState = TState.Pending, 'Deferred object already finished.');

    FSuccess := value;
    FState := TState.Resolved;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TDeferredObject<TSuccess, TFailure>.Reject(
  value: IFailureReason<TFailure>): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    AssertState(Self.GetState = TState.Pending, 'Deferred object already finished.');

    FFailure := value;
    FState := TState.Rejected;
  finally
    TMonitor.Exit(Self);
  end;
end;

{ TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure> }

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Catch(
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  Result := Self.ThenByInternal(nil, whenfailure);
end;

constructor TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Create(
  const prev: IPromiseAccess<TSuccessSource, TFailureSource>;
  const whenSucces: TPipelineFunc<TSuccessSource, TSuccess, TFailure>;
  const whenFailure: TPipelineFunc<IFailureReason<TFailureSource>, TSuccess, TFailure>);
begin
  Assert(Assigned(prev));

  FPrevPromise := prev;

  FFuture := TDeferredTask<TSuccess, TFailure>.Create(Self,
    procedure (const resolver: TProc<TSuccess>; const rejector: TFailureProc<TFailure>)
    var
      nextPromise: IPromiseAccess<TSuccess, TFailure>;
    begin
      FPrevPromise.Self.Future.WaitFor;

      nextPromise := nil;
      case FPrevpromise.State of
        TState.Resolved: begin
           Assert(Supports(whenSucces(FPrevPromise.GetValue), IPromiseAccess<TSuccess,TFailure>,nextPromise));
        end;
        TState.Rejected: begin
          Assert(Supports(whenFailure(FPrevPromise.GetFailure), IPromiseAccess<TSuccess,TFailure>,nextPromise));
        end;
      end;

      nextPromise.Self.Future.WaitFor;

      case nextPromise.State of
        TState.Resolved: begin
          resolver(nextPromise.GetValue)
        end;
        TState.Rejected: begin
          rejector(nextPromise.GetFailure);
        end;
      end;
    end
  )
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Reject(
  value: IFailureReason<TFailure>): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    FFailure := value;
    FState := TState.Rejected;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Resolve(
  value: TSuccess): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    FState := TState.Resolved;
  finally
    TMonitor.Exit(Self);
  end;
end;

destructor TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Destroy;
begin
  inherited;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Done(
  const proc: TProc<TSuccess>): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    Result := TTerminatedPromise<TSuccess, TFailure>.Create(Self).Done(proc);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Fail(
  const proc: TFailureProc<TFailure>): IPromise<TSuccess, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    Result := TTerminatedPromise<TSuccess, TFailure>.Create(Self).Fail(proc);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.ThenBy(
  const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>;
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  Assert(Assigned(whenSuccess));
  Assert(Assigned(whenFailure));

  Result := Self.ThenByInternal(whenSuccess, whenfailure);
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.ThenBy(
  const whenSuccess: TPipelineFunc<TSuccess, TSuccess, TFailure>): IPromise<TSuccess, TFailure>;
begin
  Assert(Assigned(whenSuccess));

  Result := Self.ThenByInternal(whenSuccess, nil);
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.GetFuture: IFuture<TSuccess>;
begin
  Result := FFuture;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.GetSelfInternal: IPromise<TSuccess, TFailure>;
begin
  Result := Self;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.GetStateInternal: TState;
begin
  Result := FState;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.GetValueInternal: TSuccess;
begin
  Result := FFuture.Value;
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.Op: TPromiseOp<TSuccess, TFailure>;
begin
  Result := TPromiseOp<TSuccess, TFailure>.Create(Self);
end;

function TPipedPromise<TSuccessSource, TSuccess, TFailureSource, TFailure>.GetFailureInternal: IFailureReason<TFailure>;
begin
  Result := FFailure;
end;

{ TTerminatedPromise<TResult, TFailure> }

constructor TTerminatedPromise<TResult, TFailure>.Create(
  const prev: IPromiseAccess<TResult, TFailure>);
begin
  Assert(Assigned(prev));

  FPrevPromise := prev;
  FDoneActions := TList<TProc<TResult>>.Create;
  FFailActions := TList<TFailureProc<TFailure>>.Create;

  FFuture := TDeferredTask<TResult,TFailure>.Create(Self,
    procedure (const resolver: TProc<TResult>; const rejector: TFailureProc<TFailure>)
    begin
      FPrevPromise.Self.Future.WaitFor;

      case FPrevPromise.State of
        TSTate.Resolved: begin
          resolver(FPrevPromise.GetValue);
        end;
        TSTate.Rejected: begin
          rejector(FPrevPromise.GetFailure);
        end;
      end;
    end
  );
end;

destructor TTerminatedPromise<TResult, TFailure>.Destroy;
begin
  FDoneActions.Free;
  FFailActions.Free;
  inherited;
end;

function TTerminatedPromise<TResult, TFailure>.Resolve(
  value: TResult): IPromise<TResult, TFailure>;
var
  proc: TProc<TResult>;
begin
  TMonitor.Enter(Self);
  try
    for proc in FDoneActions do begin
      proc(value);
    end;
    FState := TState.Resolved;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTerminatedPromise<TResult, TFailure>.Reject(
  value: IFailureReason<TFailure>): IPromise<TResult, TFailure>;
var
  proc: TFailureProc<TFailure>;
begin
  TMonitor.Enter(Self);
  try
    for proc in FFailActions do begin
      proc(value);
    end;
    FState := TState.Rejected;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTerminatedPromise<TResult, TFailure>.Done(
  const proc: TProc<TResult>): IPromise<TResult, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    case Self.GetState of
      TState.Pending: begin
        FDoneActions.Add(proc);
      end;
      TState.Resolved: begin
        proc(FPrevPromise.GetValue);
      end;
    end;

    Result := Self;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTerminatedPromise<TResult, TFailure>.Fail(
  const proc: TFailureProc<TFailure>): IPromise<TResult, TFailure>;
begin
  TMonitor.Enter(Self);
  try
    case Self.GetState of
      TState.Pending: begin
        FFailActions.Add(proc);
      end;
      TState.Rejected: begin
        proc(FPrevPromise.GetFailure);
      end;
    end;

    Result := Self;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTerminatedPromise<TResult, TFailure>.GetFuture: IFuture<TResult>;
begin
  Result := FFuture;
end;

function TTerminatedPromise<TResult, TFailure>.GetState: TState;
begin
  Result := FState;
end;

function TTerminatedPromise<TResult, TFailure>.Op: TPromiseOp<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

function TTerminatedPromise<TResult, TFailure>.ThenBy(
  const whenSuccess: TPipelineFunc<TResult, TResult, TFailure>;
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

function TTerminatedPromise<TResult, TFailure>.ThenBy(
  const fn: TPipelineFunc<TResult, TResult, TFailure>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

function TTerminatedPromise<TResult, TFailure>.Catch(
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

{ TPromiseValue<TResult, TFailure> }

class function TPromiseValue<TResult, TFailure>.Resolve(
  success: TResult): TPromiseValue<TResult, TFailure>;
begin
  Result := TPromiseValue<TResult, TFailure>.Create;
  Result.FSuccess := success;
  Result.FState := TSTate.Resolved;
end;

class function TPromiseValue<TResult, TFailure>.Reject(
  failure: IFailureReason<TFailure>): TPromiseValue<TResult, TFailure>;
begin
  Result := TPromiseValue<TResult, TFailure>.Create;
  Result.FFailure := failure;
  Result.FState := TSTate.Rejected;
end;

function TPromiseValue<TResult, TFailure>.GetFuture: IFuture<TResult>;
begin
  Result := TFuture.Create(FSuccess);
end;

function TPromiseValue<TResult, TFailure>.GetSelfInternal: IPromise<TResult, TFailure>;
begin
  Result := Self;
end;

function TPromiseValue<TResult, TFailure>.GetFailureInternal: IFailureReason<TFailure>;
begin
  Result := FFailure;
end;

function TPromiseValue<TResult, TFailure>.GetStateInternal: TState;
begin
  Result := FState;
end;

function TPromiseValue<TResult, TFailure>.GetValueInternal: TResult;
begin
  Result := FSuccess;
end;

function TPromiseValue<TResult, TFailure>.Op: TPromiseOp<TResult, TFailure>;
begin
  Result := TPromiseOp<TResult, TFailure>.Create(Self);
end;

function TPromiseValue<TResult, TFailure>.Catch(
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

function TPromiseValue<TResult, TFailure>.Done(
  const proc: TProc<TResult>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

function TPromiseValue<TResult, TFailure>.Fail(
  const proc: TFailureProc<TFailure>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

function TPromiseValue<TResult, TFailure>.ThenBy(
  const whenSuccess: TPipelineFunc<TResult, TResult, TFailure>;
  const whenfailure: TPipelineFunc<IFailureReason<TFailure>, TResult, TFailure>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

function TPromiseValue<TResult, TFailure>.ThenBy(
  const fn: TPipelineFunc<TResult, TResult, TFailure>): IPromise<TResult, TFailure>;
begin
  Assert(false, 'Promise pipe is not supported');
end;

{ TPromiseValue<TResult, TFailure>.TFuture<TResult> }

constructor TPromiseValue<TResult, TFailure>.TFuture.Create(value: TResult);
begin
  FValue := value;
end;

procedure TPromiseValue<TResult, TFailure>.TFuture.Cancell;
begin

end;

function TPromiseValue<TResult, TFailure>.TFuture.GetValue: TResult;
begin
  Result := FValue;
end;

function TPromiseValue<TResult, TFailure>.TFuture.WaitFor: boolean;
begin
  Result := true;
end;

end.
