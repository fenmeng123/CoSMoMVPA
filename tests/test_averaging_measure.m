function test_suite = test_averaging_measure
    initTestSuite;

function test_averaging_measure_
    ds=generate_test_dataset();

    a=cosmo_averaging_measure(ds,'ratio',.5);

    assertElementsAlmostEqual(sort(a.samples), sort(ds.samples));
    assertElementsAlmostEqual(sort(a.samples(:,10)), sort(ds.samples(:,10)));

    % check wrong inputs
    assertExceptionThrown(@()cosmo_averaging_measure(ds,'ratio',.1),'');
    assertExceptionThrown(@()cosmo_averaging_measure(ds,'ratio',3),'');

    ds.sa.chunks(:)=1;
    a=cosmo_averaging_measure(ds,'ratio',.5);
    a_=cosmo_fx(a,@(x)mean(x,1),'targets');
    assertEqual(a,a_);

    cosmo_check_dataset(a);

    ds=cosmo_slice(ds,17,2);
    ns=size(ds.samples,1);
    ds.samples=ds.sa.targets*1000+(1:ns)';

    a=cosmo_averaging_measure(ds,'ratio',.5,'nrep',10);

    % no mixing of different targets
    delta=a.samples/1000-a.sa.targets;
    assertTrue(all(.003<delta & delta<.02));
    assertElementsAlmostEqual(delta*3000,round(delta*3000));

